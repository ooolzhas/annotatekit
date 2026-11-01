// Tests for the Expo config plugin's AppDelegate transform: `node --test packaging/npm/test/`.
// Fixtures are unmodified template AppDelegates (sources in fixtures/README.txt).
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const plugin = require('../app.plugin.js');
const { addAnnotateToAppDelegate, MARKER } = plugin;

const fixture = (name) => fs.readFileSync(path.join(__dirname, 'fixtures', name), 'utf8');
const count = (haystack, needle) => haystack.split(needle).length - 1;

const SWIFT_IMPORT = `import AnnotateKit ${MARKER}`;
const SWIFT_CALL = `Annotate.install() ${MARKER}`;
const OBJC_IMPORT = `#import "AnnotateKit-Swift.h" ${MARKER}`;
const OBJC_CALL = `[AnnotateBridge installWithFile:@__FILE__]; ${MARKER}`;

const cases = [
  { file: 'expo-sdk53-AppDelegate.swift', language: 'swift', afterImport: 'import ReactAppDependencyProvider' },
  { file: 'expo-sdk55-AppDelegate.swift', language: 'swift', afterImport: 'import ReactAppDependencyProvider' },
  { file: 'rn-0.77-AppDelegate.swift', language: 'swift', afterImport: 'import ReactAppDependencyProvider' },
  { file: 'rn-0.79-AppDelegate.swift', language: 'swift', afterImport: 'import ReactAppDependencyProvider' },
  { file: 'rn-main-AppDelegate.swift', language: 'swift', afterImport: 'import UIKit' },
  { file: 'expo-sdk52-AppDelegate.mm', language: 'objcpp', afterImport: '#import <React/RCTLinkingManager.h>' },
  { file: 'rn-0.74-AppDelegate.mm', language: 'objcpp', afterImport: '#import <React/RCTBundleURLProvider.h>' },
];

for (const { file, language, afterImport } of cases) {
  test(`${file}: adds the import and the install call once`, () => {
    const out = addAnnotateToAppDelegate(fixture(file), language);
    const [importLine, callLine] = language === 'swift' ? [SWIFT_IMPORT, SWIFT_CALL] : [OBJC_IMPORT, OBJC_CALL];
    assert.equal(count(out, importLine), 1);
    assert.equal(count(out, callLine), 1);
    assert.ok(out.includes(`${afterImport}\n${importLine}\n`), 'import goes after the last existing import');
  });

  test(`${file}: the install call is the launch method's first statement`, () => {
    const out = addAnnotateToAppDelegate(fixture(file), language);
    const lines = out.split('\n');
    const signature = lines.findIndex((line) => line.includes('didFinishLaunchingWithOptions'));
    const brace = lines.findIndex((line, i) => i >= signature && line.trimEnd().endsWith('{'));
    const next = lines[brace + 1];
    assert.match(next, language === 'swift' ? /^ {4}Annotate\.install\(\)/ : /^ {2}\[AnnotateBridge installWithFile:@__FILE__\];/);
    // Indented like the statement after it
    const following = lines.slice(brace + 2).find((line) => line.trim() && !line.startsWith('#'));
    assert.equal(/^\s*/.exec(next)[0], /^\s*/.exec(following)[0]);
  });

  test(`${file}: is idempotent`, () => {
    const once = addAnnotateToAppDelegate(fixture(file), language);
    assert.equal(addAnnotateToAppDelegate(once, language), once);
  });

  test(`${file}: changes nothing but the two added lines`, () => {
    const source = fixture(file);
    const out = addAnnotateToAppDelegate(source, language);
    const removed = out
      .split('\n')
      .filter((line) => !line.includes(MARKER))
      .join('\n');
    // rn-main's single-expression body gains an explicit return; everything else is untouched
    const expected = file === 'rn-main-AppDelegate.swift' ? source.replace('    true\n', '    return true\n') : source;
    assert.equal(removed, expected);
  });
}

test('Expo SDK 53 output', () => {
  const out = addAnnotateToAppDelegate(fixture('expo-sdk53-AppDelegate.swift'), 'swift');
  assert.ok(out.startsWith(`import Expo\nimport React\nimport ReactAppDependencyProvider\n${SWIFT_IMPORT}\n\n@UIApplicationMain\n`));
  assert.ok(
    out.includes(
      ') -> Bool {\n' + `    ${SWIFT_CALL}\n` + '    let delegate = ReactNativeDelegate()\n'
    )
  );
});

test('Obj-C++ output', () => {
  const out = addAnnotateToAppDelegate(fixture('rn-0.74-AppDelegate.mm'), 'objcpp');
  assert.ok(out.startsWith(`#import "AppDelegate.h"\n\n#import <React/RCTBundleURLProvider.h>\n${OBJC_IMPORT}\n\n@implementation`));
  assert.ok(out.includes(`didFinishLaunchingWithOptions:(NSDictionary *)launchOptions\n{\n  ${OBJC_CALL}\n  self.moduleName`));
});

test('Obj-C (.m) uses the Obj-C transform', () => {
  const source = fixture('rn-0.74-AppDelegate.mm');
  assert.equal(addAnnotateToAppDelegate(source, 'objc'), addAnnotateToAppDelegate(source, 'objcpp'));
});

test('a single-expression Swift body gets an explicit return', () => {
  const out = addAnnotateToAppDelegate(fixture('rn-main-AppDelegate.swift'), 'swift');
  assert.ok(out.includes(`) -> Bool {\n    ${SWIFT_CALL}\n    return true\n  }`));
});

test('leaves an AppDelegate that already calls install alone', () => {
  const swift = fixture('rn-0.79-AppDelegate.swift').replace('let delegate =', 'Annotate.install()\n    let delegate =');
  assert.equal(addAnnotateToAppDelegate(swift, 'swift'), swift);
  const objc = fixture('rn-0.74-AppDelegate.mm').replace('self.moduleName', '[AnnotateBridge installWithFile:@__FILE__];\n  self.moduleName');
  assert.equal(addAnnotateToAppDelegate(objc, 'objcpp'), objc);
});

test('a file without imports gets the import at the top', () => {
  const swift = 'class AppDelegate {\n  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {\n    return true\n  }\n}\n';
  assert.ok(addAnnotateToAppDelegate(swift, 'swift').startsWith(`${SWIFT_IMPORT}\nclass AppDelegate {`));
});

test('throws when didFinishLaunching is missing', () => {
  const swift = fixture('rn-0.79-AppDelegate.swift').replace(/didFinishLaunchingWithOptions/g, 'somethingElse');
  assert.throws(() => addAnnotateToAppDelegate(swift, 'swift'), /application\(_:didFinishLaunchingWithOptions:\)/);
  const objc = fixture('expo-sdk52-AppDelegate.mm').replace(/didFinishLaunchingWithOptions/g, 'somethingElse');
  assert.throws(() => addAnnotateToAppDelegate(objc, 'objcpp'), /application:didFinishLaunchingWithOptions:/);
});

test('throws on an unknown language', () => {
  assert.throws(() => addAnnotateToAppDelegate('', 'kotlin'), /Unsupported AppDelegate language "kotlin"/);
});

test('loads without Expo installed and exports the plugin', () => {
  assert.equal(typeof plugin, 'function');
  assert.equal(plugin.name, 'withAnnotate');
});
