import { afterEach, expect, it, vi } from "vitest";
import { withTimeout } from "../src/services/asyncTimeout";
afterEach(() => vi.useRealTimers());
it("releases a caller whose storage request never settles", async () => {
  vi.useFakeTimers();
  const result = withTimeout(new Promise(() => {}), 3000);
  const rejected = expect(result).rejects.toThrow("timed out");
  await vi.advanceTimersByTimeAsync(3000);
  await rejected;
});
it("preserves storage failures and successful results", async () => {
  await expect(withTimeout(Promise.resolve(42), 3000)).resolves.toBe(42);
  await expect(withTimeout(Promise.reject(new Error("storage unavailable")), 3000)).rejects.toThrow("storage unavailable");
});
