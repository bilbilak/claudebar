import esbuild from 'esbuild';
import { execSync } from 'node:child_process';
import { mkdirSync, copyFileSync, rmSync, existsSync, readdirSync } from 'node:fs';
import { basename } from 'node:path';

const watch = process.argv.includes('--watch');
const outdir = 'dist';

if (existsSync(outdir)) rmSync(outdir, { recursive: true, force: true });
mkdirSync(`${outdir}/schemas`, { recursive: true });

execSync(
  `npx sass src/styles/stylesheet.scss ${outdir}/stylesheet.css --no-source-map --style=expanded`,
  { stdio: 'inherit' }
);

// Compile gettext catalogs: po/<lang>.po -> dist/locale/<lang>/LC_MESSAGES/claudebar.mo
// GNOME Shell loads these automatically because metadata.json sets gettext-domain.
if (existsSync('po')) {
  const poFiles = readdirSync('po').filter((f) => f.endsWith('.po'));
  for (const file of poFiles) {
    const lang = basename(file, '.po');
    const moDir = `${outdir}/locale/${lang}/LC_MESSAGES`;
    mkdirSync(moDir, { recursive: true });
    execSync(`msgfmt po/${file} -o ${moDir}/claudebar.mo`, { stdio: 'inherit' });
  }
}

copyFileSync('metadata.json', `${outdir}/metadata.json`);
copyFileSync(
  'schemas/org.gnome.shell.extensions.claudebar.gschema.xml',
  `${outdir}/schemas/org.gnome.shell.extensions.claudebar.gschema.xml`
);

const common = {
  bundle: true,
  format: 'esm',
  platform: 'neutral',
  target: ['es2022'],
  external: ['gi://*', 'resource://*', 'system', 'gettext', 'cairo'],
  logLevel: 'info',
};

const ctxs = await Promise.all([
  esbuild.context({
    ...common,
    entryPoints: ['src/extension.ts'],
    outfile: `${outdir}/extension.js`,
  }),
  esbuild.context({
    ...common,
    entryPoints: ['src/prefs.ts'],
    outfile: `${outdir}/prefs.js`,
  }),
]);

if (watch) {
  await Promise.all(ctxs.map((c) => c.watch()));
  console.log('Watching for changes...');
} else {
  await Promise.all(ctxs.map((c) => c.rebuild()));
  await Promise.all(ctxs.map((c) => c.dispose()));
  execSync('glib-compile-schemas dist/schemas', { stdio: 'inherit' });
  console.log('Build complete.');
}
