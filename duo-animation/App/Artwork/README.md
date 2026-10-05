# Duo Lid app icon

<img src="duo-lid-icon-1024.png" alt="Duo Lid MacBook silhouette with the closing effect inside its screen" width="256" height="256">

The icon depicts the user-supplied closing-effect state inside a simple, front-facing MacBook silhouette. It was created with the built-in OpenAI image generation tool, using [this exact prompt](icon-prompt.txt) and [the supplied reference](closing-effect-reference.png), which shows Duo Lid's generated sample desktop. No Apple logo, phone artwork or personal desktop content is included.

The selected output was exported as [duo-lid-icon-1024.png](duo-lid-icon-1024.png), a 1024×1024, opaque RGB PNG in the sRGB color space. `sips` resizes this master into the ten macOS 1×/2× variants under [AppIcon.appiconset](../Assets.xcassets/AppIcon.appiconset/), covering 16, 32, 128, 256 and 512 points. The 512-point 2× variant is the 1024-pixel App Store image. This follows Apple's [asset-catalog icon configuration](https://developer.apple.com/documentation/xcode/configuring-your-app-icon) and [macOS icon size reference](https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/IconSetType.html).

`project.yml` includes the asset catalog and sets `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. Xcode compiles `AppIcon.icns` and `Assets.car`, adds the bundle icon metadata, and packages them in the app. The preview header and About panel load the bundled icon directly. The master and reference in this folder are development artwork; the app packages the compiled catalog resources. Signing and distribution status are described in the [project README](../../../README.md).
