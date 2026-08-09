function folded(value: string): string {
  return value
    .toLocaleLowerCase("en")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
}

/** Conservative metadata heuristic; disabling the setting restores all rows. */
export function isLikelyRadioStation(
  name: string,
  categoryOrGroup?: string,
): boolean {
  return [name, categoryOrGroup ?? ""].some((value) => {
    const text = folded(value);
    return (
      /(^|[^a-z0-9])radio([^a-z0-9]|$)/.test(text) ||
      /(^|[^a-z0-9])fm([^a-z0-9]|$)/.test(text) ||
      text.indexOf("ραδιο") !== -1 ||
      text.indexOf("радио") !== -1 ||
      text.indexOf("راديو") !== -1
    );
  });
}
