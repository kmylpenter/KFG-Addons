/**
 * wycena-helpers-example.js — Reference template for project-specific smoke helpers.
 *
 * PORTING GUIDE:
 *   Copy this file to your project as:
 *     thoughts/shared/petla/smoke-helpers/<project>-helpers.js
 *   Then customize: replace 'Wycena' assertions/state-keys with your app's.
 *
 * USAGE inside test file:
 *   const helpers = require('../../smoke-helpers/wycena-helpers.js');
 *   module.exports = async function(page, dymHelpers) {
 *     await helpers.gotoAndInit(page, dymHelpers);
 *     await helpers.fillBasicForm(page, dymHelpers);
 *     await dymHelpers.snapshot('after-fill', await helpers.captureCardState(page));
 *   };
 *
 * SOURCE:
 *   Adapted from /data/data/com.termux/files/home/smoke-test/smoke-base.js
 *   (Terminator-Umowy session, 2026-05-01) using Test Author API.
 */

'use strict';

async function gotoAndInit(page, dymHelpers) {
  await page.goto(dymHelpers.baseUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForFunction(
    () => typeof _allProducts !== 'undefined' && _allProducts.length > 0
       && typeof _variantTemplatesCache !== 'undefined' && _variantTemplatesCache,
    { timeout: 20000, polling: 500 }
  );
  await dymHelpers.snapshot('init', await page.evaluate(() => ({
    products_count: _allProducts.length,
    templates_loaded: !!_variantTemplatesCache,
  })));
}

async function fillBasicForm(page, dymHelpers) {
  await page.evaluate(() => {
    if (typeof selectType === 'function') selectType('Klasyczne dywanowe');
  });
  await page.waitForFunction(
    () => typeof selectedType !== 'undefined' && selectedType
       && selectedType.id === 'Klasyczne dywanowe',
    { timeout: 5000, polling: 200 }
  );
  await page.evaluate(() => {
    const setVal = (id, val) => {
      const el = document.getElementById(id);
      if (!el) return;
      el.value = val;
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    };
    setVal('stopMat', 'Dąb');
    setVal('stopGrub', '5');
    setVal('stopnieQty', '14');
  });
  await page.evaluate(() => {
    if (typeof updatePreview === 'function') updatePreview();
    if (typeof updateProductPreview === 'function') updateProductPreview();
  });
  await page.waitForFunction(
    () => typeof _productCostSummary !== 'undefined' && _productCostSummary
       && _productCostSummary.schody > 0,
    { timeout: 8000, polling: 300 }
  ).catch(() => {});
  await dymHelpers.snapshot('after-fill', await page.evaluate(() => ({
    selected: selectedType?.id,
    cost_summary: _productCostSummary,
  })));
}

async function captureCardState(page) {
  return await page.evaluate(() => {
    const panel = document.getElementById('pricingVariantsPanel');
    const cards = panel ? panel.querySelectorAll('.variant-card') : [];
    return {
      panel_display: panel ? panel.style.display : 'NOT_FOUND',
      variant_cards_count: cards.length,
      cs: typeof _productCostSummary !== 'undefined' ? _productCostSummary : null,
    };
  });
}

module.exports = { gotoAndInit, fillBasicForm, captureCardState };
