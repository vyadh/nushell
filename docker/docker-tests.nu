#!/usr/bin/env nu
use std assert

# Usage:
# docker run -it --rm -v $"(pwd):/work" nu-debian /work/docker-tests.nu

def main [] {
    let test_plan = (
        scope commands
            | where ($it.type == "custom")
                and ($it.name | str starts-with "test ")
                and not ($it.description | str starts-with "ignore")
            | each { |test| create_execution_plan $test.name }
            | str join ", "
    )
    let plan = $"run_tests [ ($test_plan) ]"
    nu --commands $"source ($env.CURRENT_FILE); ($plan)"
}

def create_execution_plan [test: string] -> string {
    $"{ name: \"($test)\", execute: { ($test) } }"
}

def run_tests [tests: list<record<name: string, execute: closure>>] {
    let results = $tests | par-each { run_test $in }
    print $results
    print_summary $results
}

def print_summary [results: list<record<name: string, result: string>>] {
    let success = $results | where ($it.result == "✅") | length
    let failure = $results | where ($it.result == "❌") | length
    let count = $results | length

    if ($failure == 0) {
        print $"Testing completed: ($success) of ($count) were successful"
        exit 1
    } else {
        print $"Testing completed: ($failure) of ($count) failed"
    }
}

def run_test [test: record<name: string, execute: closure>] -> record<name: string, result: string, error: string> {
    try {
        print $"Running: ($test.name)"
        do ($test.execute)
        { result: "✅",name: $test.name, error: "" }
    } catch { |error|
        { result: "❌", name: $test.name, error: $"($error.msg) (format_error $error.debug)" }
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

def "test nu is pid 1 to ensure it is handling interrupts" [] {
    let process_id = ps
        | where ($it.pid == 1)
        | get name
        | first

    assert equal $process_id "nu"
}

def "test user is nushell" [] {
    assert equal (whoami) "nushell"
}

