import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import './host.mjs';

// host.mjs says it is a pure-Node mirror of kJsBootstrap, and the provider
// tests lean on that: a helper that behaves differently here than it does in
// QuickJS makes a green harness run mean nothing. So read the real bootstrap
// out of js_bootstrap.dart, evaluate it into its own bag, and compare the
// helpers that are supposed to be identical on both sides.
//
// Only the pure ones. __fetch / __console / sha256Hex / aesCtrDecrypt are
// deliberately different here (real fetch, node:crypto) instead of hopping the
// Dart bridge, and base64ToBytes disagrees on base64url input, which is its own
// question rather than harness drift.
const OPEN = "r'''";
const CLOSE = '\n' + "'''" + ';';

function loadBootstrapHelpers() {
  const dart = fs.readFileSync(
    new URL('../lib/core/provider/js_bootstrap.dart', import.meta.url), 'utf8');
  const start = dart.indexOf(OPEN, dart.indexOf('kJsBootstrap'));
  const end = dart.indexOf(CLOSE, start);
  assert.ok(start > 0 && end > start, 'could not find the kJsBootstrap string literal');
  const bag = {};
  globalThis.__BOOTSTRAP__ = bag;
  // The bootstrap hangs everything off globalThis; point that at the bag so it
  // cannot stamp over the harness's own copies of the same names.
  (0, eval)(dart.slice(start + OPEN.length, end).replace(/globalThis/g, '__BOOTSTRAP__'));
  assert.equal(typeof bag.htmlText, 'function', 'bootstrap did not define htmlText');
  return bag;
}

const app = loadBootstrapHelpers();

const PACKED_WITH_QUOTES = "eval(function(p,a,c,k,e,d){e=function(c){return(c<a?'':e(parseInt(c/a)))+((c=c%a)>35?String.fromCharCode(c+29):c.toString(36))};while(c--)if(k[c])p=p.replace(new RegExp('\\\\b'+e(c)+'\\\\b','g'),k[c]);return p}('0 1=2 3.4({5:\\'#6\\',7:\\'8%\\'});1.9({a:\"b/c\",9:\"d://e.f.g:h/i/j/k.c\"});0 l=m;',62,23,'var|player|new|Clappr|Player|parentId|vplayer|width|100|src|type|video|mp4|https|www7|mp4upload|com|282|files|abcdef|movie|HEIGHT|720'.split('|'),0,{}))";
const PACKED_WITH_QUOTES_SOURCE =
  "var player=new Clappr.Player({parentId:'#vplayer',width:'100%'});"
  + 'player.src({type:"video/mp4",src:"https://www7.mp4upload.com:282/files/abcdef/movie.mp4"});'
  + 'var HEIGHT=720;';

const CASES = {
  htmlText: [
    ['<p>Naruto &#8212; the ninja</p>'],
    ['<p>A &#x2014; B</p>'],
    ['first line\n\n   second line'],
    ['<b>plain</b> &amp; simple'],
    ['&#39;quoted&#39; &nbsp;&lt;tag&gt;'],
    [''],
    [null],
  ],
  absUrl: [
    ['https://a.test/x', 'https://b.test/'],
    ['//cdn.test/x.mp4', 'https://b.test/'],
    ['/ep/1', 'https://b.test/anime'],
    ['/ep/1', 'HTTPS://B.TEST/anime'],
    ['/ep/1', '//cdn.test/anime'],
    ['/ep/1', 'cdn.test/anime'],
    ['ep/1', 'https://b.test/anime/'],
    ['ep/1', null],
    ['', 'https://b.test/'],
    [null, 'https://b.test/'],
  ],
  unpackJs: [
    ['player.src("x")'],
    ["eval(function(p,a,c,k,e,d){}('0 1',2,2,'hello|world'.split('|'),0,{}))"],
    ["eval(function(p,a,c,k,e,d){}('z.10(A)',36,37,'|||||||||||||||||||||||||||||||||||player|src'.split('|'),0,{}))"],
    [PACKED_WITH_QUOTES],
  ],
  bytesToHex: [[[]], [[0, 1, 2, 255]], [[16, 255]]],
  bytesToB64: [[[]], [[0, 1, 2]], [[104, 105]], [[255, 255, 255, 255]]],
  base64ToBytes: [[''], ['AAEC'], ['aGVsbG8='], ['aGVsbG8'], ['AA==']],
};

const show = (args) => args.map((a) => JSON.stringify(a)).join(', ');
const call = (fn, args) => {
  try { return { value: fn(...args) }; }
  catch (e) { return { threw: e.constructor.name + ': ' + e.message }; }
};

for (const [name, inputs] of Object.entries(CASES)) {
  test(`${name} matches kJsBootstrap`, () => {
    assert.equal(typeof globalThis[name], 'function', `harness is missing ${name}`);
    for (const args of inputs) {
      const mine = call(globalThis[name], args);
      const theirs = call(app[name], args);
      assert.deepEqual(mine, theirs,
        `${name}(${show(args)}) differs: harness ${JSON.stringify(mine)} vs app ${JSON.stringify(theirs)}`);
    }
  });
}

// Parity alone would stay green with both sides broken the same way, so assert
// the contract against the real bootstrap too: `unpackJs` must hand back an
// unpacked page untouched. An ordinary embed page — a `}(jQuery));` IIFE beside
// a `.split('|')` quality list — used to come back as
// `unction($){\n  $.post('/ping`, with the player URL cut off the end.
test('kJsBootstrap unpackJs leaves an unpacked page alone', () => {
  const page = [
    '(function($){',
    "  $.post('/ping', { q: 1 });",
    "  var labels = '360p|480p|720p'.split('|');",
    '}(jQuery));',
    'player.src("https://cdn.example.test/v/abcd1234.mp4");',
  ].join('\n');
  assert.equal(app.unpackJs(page), page);
});

// Parity stayed green while both sides cut this payload at `'#vplayer',` and
// decoded its middle, so assert the contract against the real bootstrap.
test('kJsBootstrap unpackJs decodes a payload with escaped quotes', () => {
  assert.equal(app.unpackJs(PACKED_WITH_QUOTES), PACKED_WITH_QUOTES_SOURCE);
});

// AllAnime writes its apostrophes as &apos;, and the TV detail screen shows
// the description without cleaning it again.
test('kJsBootstrap htmlText decodes &apos;', () => {
  assert.equal(app.htmlText('At Gomah&apos;s side'), "At Gomah's side");
});
