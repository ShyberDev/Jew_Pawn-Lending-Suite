// P2 — Firestore security-rules test for the first-shop-creation bug.
//
// Run against the real rules with the Firestore emulator (no Firebase project,
// no credentials, no data):
//
//   cd test/emulator && npm install
//   npm test
//
// `demo-jewellery-suite` is a demo- project id: the emulator and the client SDK
// never contact Google when it is used.
import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';

const SHOP_A = 'uid-a';
const SHOP_B = 'uid-b';
const HAS_STAMP = { weight: 1.5, updated_at: '2026-11-09T06:00:00.000Z' };

let env;

const shopDoc = (owner) => ({
  owner,
  name: 'Test shop',
  members: { [owner]: true },
  updated_at: '2026-11-09T06:00:00.000Z',
});

const as = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-jewellery-suite',
    firestore: {
      rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await env.cleanup();
});

describe('first shop creation (P2)', () => {
  it('lets a new account read its own shop before it exists', async () => {
    const snap = await assertSucceeds(getDoc(doc(as(SHOP_A), 'shops', SHOP_A)));
    assert.equal(snap.exists(), false);
  });

  it('lets the owner create that shop', async () => {
    await assertSucceeds(setDoc(doc(as(SHOP_A), 'shops', SHOP_A), shopDoc(SHOP_A)));
  });

  it('reads the shop back after creation', async () => {
    const snap = await assertSucceeds(getDoc(doc(as(SHOP_A), 'shops', SHOP_A)));
    assert.equal(snap.exists(), true);
  });

  it('accepts a stock movement with updated_at', async () => {
    await assertSucceeds(
      setDoc(
        doc(collection(as(SHOP_A), 'shops', SHOP_A, 'stock_movements'), 'm1'),
        HAS_STAMP,
      ),
    );
  });

  it('rejects a stock movement without updated_at', async () => {
    await assertFails(
      setDoc(
        doc(collection(as(SHOP_A), 'shops', SHOP_A, 'stock_movements'), 'm2'),
        { weight: 1.5 },
      ),
    );
  });
});

describe('another shop stays private (P2)', () => {
  before(async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'shops', SHOP_B), shopDoc(SHOP_B));
      await setDoc(
        doc(db, 'shops', SHOP_B, 'stock_movements', 'b1'),
        HAS_STAMP,
      );
    });
  });

  it('cannot read the other shop document', async () => {
    await assertFails(getDoc(doc(as(SHOP_A), 'shops', SHOP_B)));
  });

  it('cannot read the other shop data', async () => {
    await assertFails(
      getDoc(doc(as(SHOP_A), 'shops', SHOP_B, 'stock_movements', 'b1')),
    );
  });

  it('cannot write into the other shop', async () => {
    await assertFails(
      setDoc(
        doc(as(SHOP_A), 'shops', SHOP_B, 'stock_movements', 'x'),
        HAS_STAMP,
      ),
    );
  });

  it('cannot create a shop under somebody else\'s id', async () => {
    await assertFails(
      setDoc(doc(as(SHOP_A), 'shops', 'uid-victim'), shopDoc(SHOP_A)),
    );
  });

  it('cannot hand its own shop to another account', async () => {
    await assertFails(updateDoc(doc(as(SHOP_A), 'shops', SHOP_A), { owner: SHOP_B }));
  });

  it('refuses a signed-out reader', async () => {
    await assertFails(getDoc(doc(anon(), 'shops', SHOP_A)));
  });
});
