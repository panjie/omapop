// English catalog bridge for tests that evaluate the production QML functions
// in a Node VM. Production uses Commons.Translations and QML's String.arg();
// the VM needs the same two pieces to exercise translated messages.
import { readFileSync } from "node:fs";

const catalog = JSON.parse(readFileSync(new URL("../i18n/en.json", import.meta.url), "utf8"));

export const strings = {
  t(key, fallback) {
    const value = catalog[key];
    if (typeof value === "string") return value;
    return fallback !== undefined ? fallback : key;
  },
};

export const argPolyfill = `
String.prototype.arg = function () {
  var args = Array.prototype.slice.call(arguments);
  return String(this).replace(/%([0-9]+)/g, function (match, number) {
    var index = Number(number) - 1;
    return index >= 0 && index < args.length ? String(args[index]) : match;
  });
};
`;
