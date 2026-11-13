/* Exercise exported transport rules through real browser input and saved state. */
const { chromium, webkit } = require('playwright');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const rooms = JSON.parse(fs.readFileSync('data/levels.json', 'utf8')).filter(r => r.chapter === 'Slipstream');
const geometry = JSON.parse(fs.readFileSync('builds/web-controls.json', 'utf8'))['390x664'];
const keys = {U:'ArrowUp',D:'ArrowDown',L:'ArrowLeft',R:'ArrowRight'};
const directions = {U:'up',D:'down',L:'left',R:'right'};
const readProgress = async () => {
 const request = r => new Promise((resolve,reject) => {r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)});
 for (const info of await indexedDB.databases()) {
  const db = await request(indexedDB.open(info.name));
  try {
   for (const name of db.objectStoreNames) {
    const store=db.transaction(name,'readonly').objectStore(name);
    const [keys,values]=await Promise.all([request(store.getAllKeys()),request(store.getAll())]);
    for(let i=0;i<keys.length;i++) if(typeof keys[i]==='string' && keys[i].endsWith('/echo/progress.json'))
     return JSON.parse(new TextDecoder().decode(values[i].contents));
   }
  } finally {db.close()}
 }
 return null;
};
(async()=>{
 const kind=process.env.BROWSER || 'chromium';
 const options={headless:true};
 if(process.env.BROWSER_EXECUTABLE) options.executablePath=process.env.BROWSER_EXECUTABLE;
 if(process.env.ECHO_PROXY) options.proxy={server:process.env.ECHO_PROXY};
 const browser=await ({chromium,webkit}[kind]).launch(options);
 const errors=[];
 try {
  for (const mobile of [true,false]) {
   const context=await browser.newContext(mobile ? {viewport:{width:390,height:664},isMobile:true,hasTouch:true} : {viewport:{width:1280,height:820}});
   const page=await context.newPage();
   page.on('pageerror',e=>errors.push(e.message));
   page.on('console',m=>{if(m.text().includes('ERROR:'))errors.push(m.text())});
   for(const room of mobile ? rooms : rooms.slice(-1)) {
    const address=new URL(process.env.ECHO_URL || 'http://127.0.0.1:8789/');
    address.searchParams.set('room',room.id);
    await page.goto(address.href,{waitUntil:'domcontentloaded'});
    await page.waitForFunction(()=>!document.querySelector('#status'),null,{timeout:120000});
    await page.waitForTimeout(1800);
    await page.evaluate(`window.readProgress=${readProgress}`);
    assert.equal(await page.evaluate(()=>echoViewport.touch),mobile);
    async function action(command) {
     if(mobile){
      const p=geometry[command==='seal'?'echo':directions[command]];
      const r=await page.locator('#canvas').boundingBox();
      await page.touchscreen.tap(r.x+p.x,r.y+p.y);
     } else await page.keyboard.press(command==='seal'?'Enter':keys[command]);
     await page.waitForTimeout(430);
    }
    for (const tape of room.recordings) {
     for(const letter of tape) await action(letter);
     await action('seal');
    }
    for(let i=0;i<room.final.length;i++) {
     await action(room.final[i]);
     if(i===0){
      const before=await page.evaluate(()=>readProgress());
      if(mobile){
       const p=geometry.undo;const r=await page.locator('#canvas').boundingBox();
       await page.touchscreen.tap(r.x+p.x,r.y+p.y);
      } else await page.keyboard.press('z');
      await page.waitForTimeout(430);
      await action(room.final[i]);
      const after=await page.evaluate(()=>readProgress());
      assert.deepEqual(after.session,before.session,'Undo restores a transported move exactly');
      await page.reload({waitUntil:'domcontentloaded'});
      await page.waitForFunction(()=>!document.querySelector('#status'),null,{timeout:120000});
      await page.waitForTimeout(1800);
      await page.evaluate(`window.readProgress=${readProgress}`);
      assert.deepEqual((await page.evaluate(()=>readProgress())).session,before.session,'Reload retains portal inputs and echoes');
     }
    }
    await page.waitForFunction(async id=>(await readProgress())?.completed?.[id]!=null,room.id,{timeout:10000});
    const progress=await page.evaluate(()=>readProgress());
    assert.equal(progress.completed[room.id].echoes,room.max_echoes);
    await page.screenshot({path:`builds/transport-${kind}-${mobile?'phone':'desktop'}-${room.id}.png`,scale:'css'});
    console.log(`${kind} ${mobile?'touch':'keyboard'}: ${room.id} ${room.title} completed, undo and reload verified.`);
   }
   await context.close();
  }
  assert.deepEqual(errors,[],'No engine or browser errors');
 } finally {await browser.close()}
})().catch(error=>{console.error(error);process.exitCode=1});
