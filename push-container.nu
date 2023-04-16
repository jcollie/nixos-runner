def main [
    input: string # tar.gz file containing container image to be pushed to repository
    ...tags: string # Tags to be added to pushed container image
    --registry: string = "" # container registry
    --repository: string = "" # container repository
    --no-latest-tag # Don't add "latest" tag to list of tags
    --no-drone-tag # Don't add tag calculated from DRONE_BUILD_NUMBER and DRONE_COMMIT_SHA
    --no-github-tag # Don't add tag calculated from GItHUB_RUN_NUMBER and GITHUB_SHA
] {
    env

    if not ($input | path exists) {
        print $"($input) does not exist!"
        exit 1
    }

    let tags = if not ($env | get -i PLUGIN_TAGS | is-empty) {
        $tags | append ($env.PLUGIN_TAGS | split row ',' | str trim)
    } else {
        $tags
    }

    let tags = if (not $no_latest_tag) {
        $tags | append "latest"
    } else {
        $tags
    }

    let tags = if (
        (not $no_github_tag)
         and
        (not ($env | get -i GITHUB_RUN_NUMBER | is-empty))
         and
        (not ($env | get -i GITHUB_SHA | is-empty))
    ) {
        $tags | append $"($env.GITHUB_RUN_NUMBER)-($env.GITHUB_SHA | str substring 0..8)"
    } else {
        $tags
    }

    let tags = if (
        (not $no_drone_tag)
         and
        (not ($env | get -i DRONE_BUILD_NUMBER | is-empty))
         and
        (not ($env | get -i DRONE_COMMIT_SHA | is-empty))
    ) {
        $tags | append $"($env.DRONE_BUILD_NUMBER)-($env.DRONE_COMMIT_SHA | str substring 0..8)"
    } else {
        $tags
    }

    print $tags

    let auth = {username: null, password: null}

    let auth = (
        if (
            (not ($env | get -i GITHUB_ACTOR | is-empty))
            and
            (not ($env | get -i GITHUB_TOKEN | is-empty))
        ) {
            {username: $env.GITHUB_ACTOR, password: $env.GITHUB_TOKEN}
        } else if (
            (not ($env | get -i PLUGIN_USERNAME | is-empty))
            and
            (not ($env | get -i PLUGIN_PASSWORD | is-empty))
        ) {
            {username: $env.PLUGIN_USERNAME, password: $env.PLUGIN_PASSWORD}
        } else {
            print "Unable to determine authentication parameters!"
            exit 1
        }
    )

    print $auth

    let registry = (
        if ($registry | is-empty) {
            if not ($env | get -i PLUGIN_REGISTRY | is-empty) {
                $env.PLUGIN_REGISTRY
            } else {
                print "No registry specified!"
                exit 1
            }
        } else {
            $registry
        }
    )

    let repository = (
        if ($repository | is-empty) {
            if not ($env | get -i PLUGIN_REPOSITORY | is-empty) {
                $env.PLUGIN_REPOSITORY
            } else {
                print "No repository specified!"
                exit 1
            }
        } else {
            $repository
        }
    )

    alias podman = ^podman --log-level error

    $auth.password | podman login --username $auth.username --password-stdin $registry

    let load_result = (do {podman load --input $input} | complete)
    if $load_result.exit_code != 0 {
        print $load_result.stderr
        exit 1
    }

    let old_image = ($load_result.stdout | str trim | parse "Loaded image: {image}" | get 0.image)

    print $old_image
    podman images
    $tags | each {
        |tag|
        let new_image = $"($registry)/($repository):($tag)"
        print $new_image
        let tag_result = (do { podman tag $old_image $new_image } | complete)
        if $tag_result.exit_code != 0 {
            print $tag_result.stderr
            exit 1
        }
        let push_result = (do { podman push $new_image } | complete)
        if $push_result.exit_code != 0 {
            print $push_result.stderr
            exit 1
        }
    }
    podman images
    podman logout $registry
}
