/* Run with Playwright installed (or NODE_PATH pointing at its package directory).
 * Generate builds/web-controls.json with tests/test_mobile.gd before this check.
 */
const {chromium, webkit}=require('playwright');
const fs=require('node:fs');
const assert=require('node:assert/strict');
const geometry=JSON.parse(fs.readFileSync('builds/web-controls.json','utf8'));
const readProgress=async()=>{
 const request=r=>new Promise((resolve,reject)=>{r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)});
 for(const info of await indexedDB.databases()){
  const db=await request(indexedDB.open(info.name));
  try{
   for(const name of db.objectStoreNames){
    const store=db.transaction(name,'readonly').objectStore(name);
    const [keys,values]=await Promise.all([request(store.getAllKeys()),request(store.getAll())]);
    for(let i=0;i<keys.length;i++) if(typeof keys[i]==='string' && keys[i].endsWith('/echo/progress.json'))
     return JSON.parse(new TextDecoder().decode(values[i].contents));
   }
  }finally{db.close()}
 }
 return null;
};
(async()=>{
const kind=process.env.BROWSER||'chromium';
const url=process.env.ECHO_URL||'http://127.0.0.1:8789/';
const options={headless:true};
if(kind==='chromium')options.args=['--autoplay-policy=user-gesture-required'];
if(process.env.BROWSER_EXECUTABLE)options.executablePath=process.env.BROWSER_EXECUTABLE;
const browser=await ({chromium,webkit}[kind]).launch(options);
const errors=[];
function observe(page){
 page.on('pageerror',error=>errors.push(error.message));
 page.on('console',message=>{if(message.text().includes('ERROR:'))errors.push(message.text())});
 page.on('dialog',async dialog=>{errors.push(dialog.message());await dialog.dismiss()});
}
async function ready(page){await page.waitForFunction(()=>!document.querySelector('#status'),null,{timeout:120000});await page.waitForTimeout(700);await page.evaluate(`window.readProgress=${readProgress}`)}
async function saved(page,test){await page.waitForFunction(test,null,{timeout:10000});}
const page=await browser.newPage({viewport:{width:390,height:664},deviceScaleFactor:3,isMobile:true,hasTouch:true});observe(page);
let size='390x664';
async function tap(name){const p=geometry[size][name];assert.ok(p,name);const r=await page.locator('#canvas').boundingBox();await page.touchscreen.tap(r.x+p.x,r.y+p.y);await page.waitForTimeout(180)}
try{
 await page.goto(url,{waitUntil:'domcontentloaded'});
 await page.screenshot({path:`builds/web-${kind}-loading.png`,scale:'css'});
 await ready(page);
 assert.deepEqual(await page.evaluate(()=>[echoViewport.touch,canvas.width,canvas.height]),[true,585,996]);
 await page.screenshot({path:`builds/web-${kind}-home.png`,scale:'css'});
 await tap('start');await page.waitForTimeout(1700);
 await page.screenshot({path:`builds/web-${kind}-phone.png`,scale:'css'});
 const beforeGuide=await page.evaluate(()=>readProgress());
 await tap('guide');await page.waitForTimeout(4400);
 await page.screenshot({path:`builds/web-${kind}-guide.png`,scale:'css'});
 await page.keyboard.press('r');
 assert.deepEqual(await page.evaluate(()=>readProgress()),beforeGuide);
 await tap('guide_close');
 // Holding a direction must never repeat; arbitrary browser finger IDs work.
 if(kind==='chromium'){
  const cdp=await page.context().newCDPSession(page); const p=geometry[size].up;
  await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{...p,id:47}]});
  await page.waitForTimeout(900);
  await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
 }else await tap('up');
 await saved(page,async()=> (await readProgress())?.session?.draft?.length===2);
 await tap('up');
 await saved(page,async()=> (await readProgress())?.session?.draft?.length===3);
 await tap('echo');
 await saved(page,async()=> (await readProgress())?.session?.echoes?.length===1);
 await tap('right');await tap('right');
 await saved(page,async()=> (await readProgress())?.session?.draft?.length===3);
 // Reflow while the echo is opening a gate; preserve the exact round.
 const before=await page.evaluate(()=>readProgress());
 await tap('back');
 await tap('chapters');
 await tap('extra');
 await tap('X04');
 await page.waitForTimeout(1700);
 await page.screenshot({path:`builds/web-${kind}-extra.png`,scale:'css'});
 const finale = JSON.parse(fs.readFileSync('data/extra.json', 'utf8')).find(room => room.id === 'X04');
 const arrows = {U: 'up', D: 'down', L: 'left', R: 'right'};
 for (const tape of finale.recordings) {
  for (const direction of tape) await tap(arrows[direction]);
  await tap('echo');
 }
 for (const direction of finale.final) await tap(arrows[direction]);
 await saved(page, async () => (await readProgress())?.extra_completed?.X04?.echoes === 2);
 const afterExtra = await page.evaluate(() => readProgress());
 assert.deepEqual(afterExtra.session, before.session);
 assert.deepEqual(afterExtra.completed, before.completed);
 // A shared room link should land on the challenge and preserve the campaign.
 const sharedRoom = new URL(url);
 sharedRoom.searchParams.set('room', 'X04');
 await page.goto(sharedRoom.href);
 await ready(page);
 await saved(page, async () => (await readProgress())?.extra_sessions?.X04?.level_id === 'X04');
 await page.waitForTimeout(1500);
 await page.screenshot({path:`builds/web-${kind}-switchyard.png`,scale:'css'});
 const north = JSON.parse(fs.readFileSync('tests/switchyard_routes.json', 'utf8'))[0];
 for (const tape of north.recordings) {
  for (const direction of tape) await tap(arrows[direction]);
  await tap('echo');
 }
 for (const direction of north.final) await tap(arrows[direction]);
 await saved(page, async () => (await readProgress())?.extra_completed?.X04?.echoes === 2);
 const afterSwitchyard = await page.evaluate(() => readProgress());
 assert.deepEqual(afterSwitchyard.session, before.session);
 assert.deepEqual(afterSwitchyard.completed, before.completed);
 await page.goto(url);
 await ready(page);
 await tap('start');
 await page.waitForTimeout(1700);
 await page.setViewportSize({width:844,height:390});size='844x390';await page.waitForTimeout(800);
 assert.deepEqual((await page.evaluate(()=>readProgress())).session,before.session);
 await page.screenshot({path:`builds/web-${kind}-landscape.png`,scale:'css'});
 await tap('undo');await tap('right');await tap('right');await tap('right');
 await saved(page,async()=> (await readProgress())?.completed?.['01']?.beats===4);
 await page.screenshot({path:`builds/web-${kind}-complete.png`,scale:'css'});
 await page.reload();await ready(page);
 assert.equal((await page.evaluate(()=>readProgress())).completed['01'].beats,4);
 await page.setViewportSize({width:390,height:664});size='390x664';await page.waitForTimeout(800);
 await tap('settings');await page.waitForTimeout(500);
 await tap('chinese');await saved(page,async()=> (await readProgress())?.language==='zh_CN');
 await page.screenshot({path:`builds/web-${kind}-chinese.png`,scale:'css'});
 await page.setViewportSize({width:320,height:568});size='320x568';await page.waitForTimeout(700);
 await page.screenshot({path:`builds/web-${kind}-small-settings.png`,scale:'css'});
 await tap('settings_back');await tap('start');await page.waitForTimeout(1800);
 await page.screenshot({path:`builds/web-${kind}-small.png`,scale:'css'});
 // CSS safe-area offsets affect rendering and input coordinates together.
 await page.setViewportSize({width:844,height:300});size='844x300';await page.waitForTimeout(700);
 await page.screenshot({path:`builds/web-${kind}-short.png`,scale:'css'});
 await page.evaluate(()=>{document.getElementById('game').style.inset='0 47px 21px'});await page.waitForTimeout(700);
 assert.deepEqual(await page.evaluate(()=>[echoViewport.width,echoViewport.height,canvas.width,canvas.height]),[750,279,1125,418]);
 await page.screenshot({path:`builds/web-${kind}-safe-area.png`,scale:'css'});
 await page.evaluate(()=>{document.getElementById('game').style.inset=''});await page.waitForTimeout(700);
 await page.reload();await ready(page);
 assert.equal((await page.evaluate(()=>readProgress())).language,'zh_CN');
 // Share the new chapter finale directly and solve it through touch controls.
 await page.setViewportSize({width:390,height:664});size='390x664';
 const carnival = new URL(url);carnival.searchParams.set('room','21');
 await page.goto(carnival.href);await ready(page);await page.waitForTimeout(1700);
 await page.screenshot({path:`builds/web-${kind}-wonderland.png`,scale:'css'});
 const ride=JSON.parse(fs.readFileSync('data/levels.json','utf8')).find(room=>room.id==='21');
 for(const tape of ride.recordings){for(const direction of tape)await tap(arrows[direction]);await tap('echo')}
 for(const direction of ride.final)await tap(arrows[direction]);
 await saved(page,async()=> (await readProgress())?.completed?.['21']?.echoes===2);
 await page.close();
 // Separate browser profile, real desktop input, no pad, and same puzzle rules.
 const desktop=await browser.newPage({viewport:{width:1280,height:820},deviceScaleFactor:1});observe(desktop);
 await desktop.goto(url);await ready(desktop);
 assert.equal(await desktop.evaluate(()=>echoViewport.touch),false);
 await desktop.mouse.click(geometry['1280x820'].start.x,geometry['1280x820'].start.y);
 await desktop.waitForTimeout(1700);
 await desktop.screenshot({path:`builds/web-${kind}-desktop.png`,scale:'css'});
 for(const key of ['ArrowUp','ArrowUp','Enter','ArrowRight','ArrowRight','ArrowRight','ArrowRight']){
  await desktop.keyboard.press(key);await desktop.waitForTimeout(150);
 }
 await saved(desktop,async()=> (await readProgress())?.completed?.['01']?.beats===4);
 await desktop.close();
 const failure=await browser.newPage();
 await failure.route('**/index.js',route=>route.abort());await failure.goto(url);
 assert.equal(await failure.locator('#retry').isVisible(),true);
 await failure.close();
 assert.deepEqual(errors,[]);
 console.log(`${kind}: phone/desktop input, Extra and Wonderland completion, campaign resume, undo, rotation, safe areas, Chinese, persistent progress, loader recovery passed.`);
}finally{await browser.close()}
})().catch(error=>{console.error(error);process.exitCode=1});
