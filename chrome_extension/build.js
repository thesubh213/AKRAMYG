const esbuild = require('esbuild');
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const isWatch = args.includes('--watch');

const distDir = path.join(__dirname, 'dist');

// Ensure dist directory exists
if (!fs.existsSync(distDir)) {
  fs.mkdirSync(distDir);
}

// Copy assets
function copyAssets() {
  const assets = ['manifest.json', 'popup.html', 'interstitial.html'];
  assets.forEach(asset => {
    const srcPath = path.join(__dirname, asset);
    const destPath = path.join(distDir, asset);
    if (fs.existsSync(srcPath)) {
      fs.copyFileSync(srcPath, destPath);
      console.log(`Copied ${asset} to dist/`);
    } else {
      console.warn(`Warning: ${asset} not found in root directory.`);
    }
  });
}

async function run() {
  copyAssets();

  const ctx = await esbuild.context({
    entryPoints: [
      'src/background.ts',
      'src/content.ts',
      'src/popup.ts',
      'src/interstitial.ts'
    ],
    bundle: true,
    outdir: 'dist',
    target: ['chrome100'],
    platform: 'browser',
    minify: false, // Keep readable for inspection/debugging in v1
    sourcemap: true,
  });

  if (isWatch) {
    console.log('Watching for changes...');
    await ctx.watch();
  } else {
    await ctx.rebuild();
    await ctx.dispose();
    console.log('Build completed successfully.');
  }
}

run().catch((err) => {
  console.error('Build failed:', err);
  process.exit(1);
});
