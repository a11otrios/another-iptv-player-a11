import { isWebOS } from "../env/platform";
import { Html5VideoAdapter } from "./Html5VideoAdapter";
import { PlayerPort } from "./PlayerPort";
import { WebOSVideoAdapter } from "./WebOSVideoAdapter";

export function createPlayer(): PlayerPort {
  return isWebOS() ? new WebOSVideoAdapter() : new Html5VideoAdapter();
}
