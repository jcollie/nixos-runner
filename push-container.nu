def main [
    input: string # tar.gz file containing container image to be pushed to repository
    ...tags: string # Tags to be added to pushed container image
    --no-latest-tag # Don't add "latest" tag to list of tags
    --no-drone-tag # Don't add tag calculated from DRONE_BUILD_NUMBER and DRONE_COMMIT_SHA
    --no-github-tag # Don't add tag calculated from GItHUB_RUN_NUMBER and GITHUB_SHA
] {
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

    let tags = if (
        (not $no_github_tag)
         and
        (not ($env | get -i GITHUB_RUN_NUMBER | is-empty))
         and
        (not ($env | get -i GITHUB_SHA | is-empty))
    ) {
        $tags | append $"($env.DRONE_BUILD_NUMBER)-($env.DRONE_COMMIT_SHA | str substring 0..8)"
    } else {
        $tags
    }

    print $tags

    if ($env | get -i PLUGIN_PASSWORD | is-empty) {
        print "No password specified!"
        exit 1
    }
    if ($env | get -i PLUGIN_USERNAME | is-empty) {
        print "No username specified!"
        exit 1
    }
    if ($env | get -i PLUGIN_REGISTRY | is-empty) {
        print "No registry specified!"
        exit 1
    }
    if ($env | get -i PLUGIN_REPOSITORY | is-empty) {
        print "No repositiory specified!"
        exit 1
    }

    alias podman = podman --log-level error

    $env.PLUGIN_PASSWORD | podman login --username $env.PLUGIN_USERNAME --password-stdin $env.PLUGIN_REGISTRY

    let load_result = (do {podman load --input $input} | complete)
    if $load_result.exit_code != 0 {
        print $load_result.stderr
        exit 1
    }
    let old_image = $load_result.stdout | str trim | parse "Loaded image: {image}" | get 0.image

    print $old_image
    podman images
    $tags | each {
        |tag|
        let new_image = $"($env.PLUGIN_REGISTRY)/($env.PLUGIN_REPOSITORY):($tag)"
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
    podman logout $env.PLUGIN_REGISTRY
}
