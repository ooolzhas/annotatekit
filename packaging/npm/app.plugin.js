// Expo config plugin for AnnotateKit (iOS only): `"plugins": ["annotate-ios"]` in app.json.
// On `npx expo prebuild` it adds the import and the install call to the generated AppDelegate.
// The pod itself is linked by autolinking from AnnotateKit.podspec at this package's root.
// Exports the plugin, plus addAnnotateToAppDelegate(contents, language) as a pure transform.
'use strict';

const MARKER = '// @generated annotate-ios';
const DOCS = 'https://github.com/ooolzhas/annotatekit#react-native-and-expo';

const SWIFT = {
  name: 'application(_:didFinishLaunchingWithOptions:)',
  // `[^{]*` stops at the body's brace: the signature itself has none
  method: /^([ \t]*)(?:[\w@]+[ \t]+)*func[ \t]+application\s*\(\s*_\s+\w+\s*:\s*UIApplication\s*,\s*didFinishLaunchingWithOptions\b[^{]*\{/m,
  importLine: /^[ \t]*(?:@\w+[ \t]+)*(?:(?:public|package|internal|fileprivate|private)[ \t]+)?import[ \t]+[\w.]+.*$/gm,
  addImport: `import AnnotateKit ${MARKER}`,
  addCall: `Annotate.install() ${MARKER}`,
};

// The Swift header, quoted: with a static-library pod (React Native's default) CocoaPods keeps
// it in "Swift Compatibility Header/", which AnnotateKit.podspec adds to the app's header search
// path; with use_frameworks! it's found in the framework's Headers. `<AnnotateKit/...>` only
// works with frameworks, and `@import` fails in .mm files without -fcxx-modules.
const OBJC = {
  name: 'application:didFinishLaunchingWithOptions:',
  method: /^([ \t]*)-\s*\(\s*BOOL\s*\)\s*application\s*:\s*\(\s*UIApplication\s*\*\s*\)\s*\w+\s+didFinishLaunchingWithOptions\s*:[^{]*\{/m,
  importLine: /^[ \t]*#[ \t]*(?:import|include)\b.*$/gm,
  addImport: `#import "AnnotateKit-Swift.h" ${MARKER}`,
  addCall: `[AnnotateBridge installWithFile:@__FILE__]; ${MARKER}`,
};

const ALREADY_INSTALLED = /Annotate\.install\s*\(|AnnotateBridge\s+installWithFile\s*:/;

/**
 * Adds AnnotateKit to an AppDelegate's source. Idempotent: returns `contents` unchanged when
 * it already carries the marker or an install call. Throws when the launch method isn't found,
 * so a template change fails the prebuild instead of silently skipping the install.
 * @param {string} contents AppDelegate source
 * @param {'swift' | 'objc' | 'objcpp'} language as reported by withAppDelegate's modResults
 * @returns {string}
 */
function addAnnotateToAppDelegate(contents, language) {
  const syntax = language === 'swift' ? SWIFT : language === 'objc' || language === 'objcpp' ? OBJC : null;
  if (!syntax) {
    throw new Error(`[annotate-ios] Unsupported AppDelegate language "${language}". Expected swift, objc or objcpp.`);
  }
  if (contents.includes(MARKER) || ALREADY_INSTALLED.test(contents)) return contents;

  const method = syntax.method.exec(contents);
  if (!method) {
    throw new Error(
      `[annotate-ios] Couldn't find ${syntax.name} in the AppDelegate, so AnnotateKit wasn't installed. ` +
        `Add the install call by hand (${DOCS}) and remove "annotate-ios" from your app.json plugins.`
    );
  }

  // 1. The install call, as the method's first line
  const methodIndent = method[1];
  const bodyStart = method.index + method[0].length;
  const indent = bodyIndent(contents.slice(bodyStart), methodIndent);
  let body = contents.slice(bodyStart);
  if (syntax === SWIFT) body = makeReturnExplicit(body);
  let result = `${contents.slice(0, bodyStart)}\n${indent}${syntax.addCall}${body}`;

  // 2. The import, after the last import above the method (or at the top)
  const head = result.slice(0, method.index);
  let lastImportEnd = -1;
  for (const match of head.matchAll(syntax.importLine)) lastImportEnd = match.index + match[0].length;
  result =
    lastImportEnd === -1
      ? `${syntax.addImport}\n${result}`
      : `${result.slice(0, lastImportEnd)}\n${syntax.addImport}${result.slice(lastImportEnd)}`;
  return result;
}

// Indentation of the body's first statement; preprocessor lines and a closing brace don't count
function bodyIndent(body, methodIndent) {
  for (const line of body.split('\n').slice(1)) {
    if (!line.trim() || /^\s*#/.test(line)) continue;
    const indent = /^[ \t]*/.exec(line)[0];
    if (line.trim().startsWith('}') || indent.length <= methodIndent.length) break;
    return indent;
  }
  return `${methodIndent}  `;
}

// A single-expression Swift body (`{ true }`) returns implicitly; once a statement is added in
// front of it, it needs an explicit `return`
function makeReturnExplicit(body) {
  let depth = 1;
  let end = -1;
  for (let i = 0; i < body.length && end === -1; i++) {
    if (body[i] === '{') depth++;
    else if (body[i] === '}' && --depth === 0) end = i;
  }
  if (end === -1) return body;
  const inner = body.slice(0, end);
  const statement = inner.trim();
  if (!statement || statement.includes('\n') || /^(return|#|\/\/)/.test(statement)) return body;
  const at = inner.indexOf(statement);
  return `${body.slice(0, at)}return ${body.slice(at)}`;
}

function withAnnotate(config) {
  // Required here, not at the top, so the transform above loads without Expo installed
  const { withAppDelegate } = require('expo/config-plugins');
  return withAppDelegate(config, (mod) => {
    mod.modResults.contents = addAnnotateToAppDelegate(mod.modResults.contents, mod.modResults.language);
    return mod;
  });
}

module.exports = withAnnotate;
module.exports.addAnnotateToAppDelegate = addAnnotateToAppDelegate;
module.exports.MARKER = MARKER;
