/// Build-time deployment identity.
///
/// The normal build is an installed build. Portable packages are compiled with
/// `--dart-define=JO_DEPLOYMENT=portable`, so the mode is fixed in the binary
/// instead of being editable through a marker file or inferred from a path.
const String kAppDeployment = String.fromEnvironment(
  'JO_DEPLOYMENT',
  defaultValue: 'installed',
);

const bool kIsPortableBuild = kAppDeployment == 'portable';

/// Native title used before localized UI is available.
const String kDefaultWindowTitle = kIsPortableBuild
    ? 'JO-AIClient Portable'
    : 'JO-AIClient';

/// Returns the localized application name for the current build identity.
String appDisplayName(String baseName, String portableName) =>
    kIsPortableBuild ? portableName : baseName;
