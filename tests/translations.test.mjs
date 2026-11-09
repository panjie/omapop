// Keep every shipped catalog complete and interpolation-compatible.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const read = code => JSON.parse(readFileSync(new URL(`../i18n/${code}.json`, import.meta.url), "utf8"));
const english = read("en");
const catalogs = { "zh-CN": read("zh-CN"), "zh-TW": read("zh-TW") };

test("catalogs carry every English key and no extras", () => {
  for (const [code, catalog] of Object.entries(catalogs)) {
    assert.deepEqual(Object.keys(catalog).sort(), Object.keys(english).sort(), code);
  }
});

test("catalog values are non-empty and keep English placeholders", () => {
  for (const [code, catalog] of Object.entries(catalogs)) {
    for (const [key, value] of Object.entries(catalog)) {
      assert.equal(typeof value, "string", `${code} ${key}`);
      assert(value.length > 0, `${code} ${key} is empty`);
      const placeholders = text => [...text.matchAll(/%[0-9]+/g)].map(match => match[0]).sort();
      assert.deepEqual(placeholders(value), placeholders(english[key]), `${code} ${key}`);
    }
  }
});
