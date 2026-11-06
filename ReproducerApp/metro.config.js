const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');

/**
 * Metro configuration
 * https://reactnative.dev/docs/metro
 *
 * @type {import('@react-native/metro-config').MetroConfig}
 */
const config = {
  resolver: {
    // A resolver that fails with a plain Error, which Metro has no error kind for: it answers the bundle request with an
    // InternalError.
    resolveRequest: (context, moduleName, platform) => {
      if (moduleName === './throws-in-the-resolver') {
        throw new Error('this resolver throws');
      }
      return context.resolveRequest(context, moduleName, platform);
    },
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
