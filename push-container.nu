def main [
    input: string # tar.gz file containing container image to be pushed to repository
    ...tags: string # Tags to be added to pushed container image
    --username: string = "" # username
    --password: string = "" # password
    --registry: string = "" # container registry
    --repository: string = "" # container repository
    --no-latest-tag # Don't add "latest" tag to list of tags
    --no-drone-tag # Don't add tag calculated from DRONE_BUILD_NUMBER and DRONE_COMMIT_SHA
    --no-github-tag # Don't add tag calculated from GITHUB_RUN_NUMBER and GITHUB_SHA
] {
    if not ($input | path exists) {
        print $"($input) does not exist!"
        exit 1
    }

    let tags = if not ($env | get -i PLUGIN_TAGS | is-empty) {
        $tags | append ($env.PLUGIN_TAGS | split row ',' | str trim)
    } else if not ($env | get -i INPUT_TAGS | is-empty) {
        $tags | append ($env.INPUT_TAGS | split row ',' | str trim)
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

    let tags = if (not $no_latest_tag) {
        $tags | append "latest"
    } else {
        $tags
    }

    let auth = {username: null, password: null}

    let auth = (
        if not ($username | is-empty) and ($password | is-empty) {
            print "Got username and password from command line"
            {username: $username, password: $password}
        } else if (
            (not ($env | get -i USERNAME | is-empty))
            and
            (not ($env | get -i PASSWORD | is-empty))
        ) {
            print "Got username and password from USERNAME and PASSWORD"
            {username: $env.USERNAME, password: $env.PASSWORD}
        } else if (
            (not ($env | get -i PLUGIN_USERNAME | is-empty))
            and
            (not ($env | get -i PLUGIN_PASSWORD | is-empty))
        ) {
            print "Got username and password from PLUGIN_USERNAME and PLUGIN_PASSWORD"
            {username: $env.PLUGIN_USERNAME, password: $env.PLUGIN_PASSWORD}
        } else if (
            (not ($env | get -i INPUT_USERNAME | is-empty))
            and
            (not ($env | get -i INPUT_PASSWORD | is-empty))
        ) {
            print "Got username and password from INPUT_USERNAME and INPUT_PASSWORD"
            {username: $env.INPUT_USERNAME, password: $env.INPUT_PASSWORD}
        } else if (
            (not ($env | get -i GITHUB_ACTOR | is-empty))
            and
            (not ($env | get -i GITHUB_TOKEN | is-empty))
        ) {
            print "Got username and password from GITHUB_ACTOR and GITHUB_TOKEN"
            {username: $env.GITHUB_ACTOR, password: $env.GITHUB_TOKEN}
        } else {
            print "Unable to determine authentication parameters!"
            exit 1
        }
    )

    let registry = (
        if ($registry | is-empty) {
            if not ($env | get -i PLUGIN_REGISTRY | is-empty) {
                $env.PLUGIN_REGISTRY
            } else if not ($env | get -i INPUT_REGISTRY | is-empty) {
                $env.INPUT_REGISTRY
            } else if not ($env | get -i REGISTRY | is-empty) {
                $env.REGISTRY
            } else if (
                (not ($env | get -i GITHUB_SERVER_URL | is-empty))
                and
                (not ($env | get -i GITHUB_ACTOR | is-empty))
            ) {
                $"($env.GITHUB_SERVER_URL)/($env.GITHUB_ACTOR)"
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
            } else if not ($env | get -i INPUT_REPOSITORY | is-empty) {
                $env.INPUT_REPOSITORY
            } else if not ($env | get -i REPOSITORY | is-empty) {
                $env.REPOSITORY
            } else {
                print "No repository specified!"
                exit 1
            }
        } else {
            $repository
        }
    )

    print $"Registry: ($registry)"
    print $"Repository: ($repository)"

    regctl --verbosity debug registry login $registry --user $auth.username --pass $auth.password

    $tags | enumerate | each {
        |item|
        if $item.index == 0 {
            let new_image = $"($registry)/($repository):($item.item)"
            print $"Pushing ($new_image)"
            regctl --verbosity debug image import $new_image $input
            print $"Pushed ($new_image)"
        } else {
            let old_image = $"($registry)/($repository):($tags | get 0)"
            let new_image = $"($registry)/($repository):($item.item)"
            print $"Copying ($old_image) ($new_image)"
            regctl --verbosity debug image copy $old_image $new_image
            print $"Copied ($old_image) ($new_image)"
        }
    }

    regctl registry logout $registry
}
