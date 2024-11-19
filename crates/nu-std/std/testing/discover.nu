use std/assert

const default_pattern = "**/{*_test,test_*}.nu"

# Usage:
#  cd crates/nu-std
#  nu -c 'use std/testing; testing list-files .'

# Test commands?
# test all
# test file <file>
# test path <path>

export def list-files [
    path: string
    pattern: string = $default_pattern
] -> list<string> {

    cd $path
    glob $pattern
}

export def list-tests [file: string] -> list<string> {
    let tests = list-files $file $default_pattern
        | each { list-tests-internal $in }

    print ($tests | table --expand)
    $tests

#    do {
#        source $file
#    }
}

def list-tests-internal [file: string] -> record {
    let query = test-query $file
    let result = (^$nu.current-exe --no-config-file --commands $query)
        | complete

    print $result

    if $result.exit_code == 0 {
        { name: $file, tests: ($result.stdout | from nuon) }
    } else {
        error make { msg: $result.stderr }
    }
}

def test-query [file: string] -> string {
    let query = "
        scope commands
            | where ( $it.type == 'custom' and $it.description =~ '\\[[a-z]+\\]' )
            | each { |test| {
                name: $test.name
                type: (
                    $test.description
                        | parse --regex '.*\\[([a-z]+)\\].*'
                        | get capture0
                        | first
                )
            } }
            | to nuon
    "
    $"source ($file); ($query)"
}


# [test]
def discover-commands-with-annotations [] {
    let temp = mktemp --directory
    let test_file_1 = $temp | path join "test_1.nu"
    let test_file_2 = $temp | path join "test_2.nu"

    "
    #[test]
    def test_foo [] { }
    # [test]
    def test_bar [] { }
    " | save $test_file_1

    "
    # [test]
    def test_baz [] { }
    def test_qux [] { }
    # [other]
    def test_quux [] { }
    " | save $test_file_2

    let result = list-tests $temp | sort

    assert equal $result [
        {
            name: $test_file_1
            tests: [
                { name: "test_bar", type: "test" }
                { name: "test_foo", type: "test" }
            ]
        }
        {
            name: $test_file_2
            tests: [
                { name: "test_baz", type: "test" }
                { name: "test_quux", type: "other" }
            ]
        }
    ]

    # todo remove in #[after-each]
    rm --recursive $temp
}

# todo failure executing nu command


def main [] {
    let test_plan = (
        scope commands
            | where ($it.type == "custom")
                and ($it.description | str starts-with "[test]")
                and not ($it.description | str starts-with "[ignore]")
            | each { |test| create_execution_plan $test.name }
            | str join ", "
    )
    let plan = $"run_tests [ ($test_plan) ]"
    ^$nu.current-exe --commands $"source ($env.CURRENT_FILE); ($plan)"
}

def create_execution_plan [test: string] -> string {
    $"{ name: \"($test)\", execute: { ($test) } }"
}

def run_tests [tests: list<record<name: string, execute: closure>>] {
    let results = $tests | each { run_test $in }

    print_results $results
    print_summary $results

    if ($results | any { |test| $test.result == "FAIL" }) {
        exit 1
    }
}

def print_results [results: list<record<name: string, result: string>>] {
    let display_table = $results | update result { |row|
        let emoji = if ($row.result == "PASS") { "✅" } else { "❌" }
        $"($emoji) ($row.result)"
    }

    if ("GITHUB_ACTIONS" in $env) {
        print ($display_table | to md --pretty)
    } else {
        print $display_table
    }
}

def print_summary [results: list<record<name: string, result: string>>] -> bool {
    let success = $results | where ($it.result == "PASS") | length
    let failure = $results | where ($it.result == "FAIL") | length
    let count = $results | length

    if ($failure == 0) {
        print $"\nTesting completed: ($success) of ($count) were successful"
    } else {
        print $"\nTesting completed: ($failure) of ($count) failed"
    }
}

def run_test [test: record<name: string, execute: closure>] -> record<name: string, result: string, error: string> {
    try {
        do ($test.execute)
        { result: $"PASS",name: $test.name, error: "" }
    } catch { |error|
        { result: $"FAIL", name: $test.name, error: $"($error.msg) ($error.debug)" }
    }
}

def format_error [error: string] {
    $error
        # Get the value for the text key in a partly non-json error message
        | parse --regex ".+text: \"(.+)\""
        | first
        | get capture0
        | str replace --all --regex "\\\\n" " "
        | str replace --all --regex " +" " "
}
