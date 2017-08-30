# Determine OS
UNAME=`uname`;
if [[ $UNAME == "Darwin" ]];
then
    OS="macos";
else
    if [[ $UNAME == "Linux" ]];
    then
        UBUNTU_RELEASE=`lsb_release -a 2>/dev/null`;
        if [[ $UBUNTU_RELEASE == *"15.10"* ]];
        then
            OS="ubuntu1510";
        else
            OS="ubuntu1404";
        fi
    else
        echo "Unsupported Operating System: $UNAME";
    fi
fi
echo "🖥 Operating System: $OS";

if [[ $OS != "macos" ]];
then
    echo "📚 Installing Dependencies"
    sudo apt-get install -y clang libicu-dev uuid-dev

    echo "🐦 Installing Swift";
    echo "Version: ${VERSION}";
    if [[ $OS == "ubuntu1510" ]];
    then
        SWIFTFILE="swift-${VERSION}-RELEASE-ubuntu15.10";
    else
        SWIFTFILE="swift-${VERSION}-RELEASE-ubuntu14.04";
    fi
    wget https://swift.org/builds/swift-$VERSION-release/$OS/swift-$VERSION-RELEASE/$SWIFTFILE.tar.gz
    tar -zxf $SWIFTFILE.tar.gz
    export PATH=$PWD/$SWIFTFILE/usr/bin:"${PATH}"
fi

echo "📅 Version: `swift --version`";

echo "🔎 Testing";

swift test
if [[ $? != 0 ]]; 
then 
    echo "❌ Tests failed";
    exit 1; 
fi

echo "✅ Done"
