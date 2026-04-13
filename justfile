build:
    swift build -c release

bundle: build
    bash scripts/bundle.sh

run: bundle
    open MicMixer.app

install: bundle
    cp -r MicMixer.app /Applications/
    echo "Installed to /Applications/MicMixer.app"

clean:
    swift package clean
    rm -rf MicMixer.app

release version:
    #!/bin/bash
    set -euo pipefail
    just bundle
    ditto -c -k --keepParent MicMixer.app MicMixer.app.zip
    gh release create "v{{version}}" MicMixer.app.zip --generate-notes --title "v{{version}}"
    rm MicMixer.app.zip
    echo "Released v{{version}}"

fmt:
    swift format --recursive Sources/

lint:
    swift format --lint --recursive Sources/
