// Copyright 2024 The WootzApp Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import {sendWithPromise} from 'chrome://resources/js/cr.js';

/** @type {?BrowserBridge} */
let instance = null;

/**
 * This class provides a "bridge" for communicating between the javascript and
 * the browser.
 */
export class BrowserBridge {
  constructor() {}

  //--------------------------------------------------------------------------
  // Messages sent to the browser
  //--------------------------------------------------------------------------
  /**
   * Sends a request to set network throttling conditions.
   * @param {boolean} offline Whether the network is simulated as offline.
   * @param {number} latency Latency in milliseconds.
   * @param {number} downloadThroughput Download throughput in bytes/second.
   * @param {number} uploadThroughput Upload throughput in bytes/second.
   * @param {number} packetLoss Percentage of packets lost (between 0 and 1).
   * @returns {Promise} A promise that resolves when the action is complete.
   */
  sendSetNetworkThrottling(offline, latency, downloadThroughput, uploadThroughput, packetLoss) {
    return sendWithPromise('setNetworkThrottling', offline, latency, downloadThroughput, uploadThroughput, packetLoss);
  }

  static getInstance() {
    return instance || (instance = new BrowserBridge());
  }
}