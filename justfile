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

fmt:
    swift format --recursive Sources/

lint:
    swift format --lint --recursive Sources/
