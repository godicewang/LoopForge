#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repository_dir="${script_dir:h}"
output_dir="${repository_dir}/docs/examples/completion-report"

cd "${repository_dir}"
LOOPFORGE_REPORT_EXAMPLE_OUTPUT="${output_dir}" \
  swift test --filter DocumentationReportFixtureTests/testGenerateCompletionReportDocumentationFixtureWhenRequested

echo "Generated ${output_dir}/index.html"
