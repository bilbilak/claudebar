import esbuild from 'esbuild';
import { execSync } from 'node:child_process';
import { mkdirSync, copyFileSync, rmSync, existsSync } from 'node:fs';

const watch = process.argv.includes('--watch');
const outdir = 'dist';

if (existsSync(outdir)) rmSync(outdir, { recursive: true, force: true });
mkdirSync(`${outdir}/schemas`, { recursive: true });

execSync(
  `npx sass src/styles/stylesheet.scss ${outdir}/stylesheet.css --no-source-map --style=expanded`,
  { stdio: 'inherit' }
);

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
