import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {test} from 'node:test';
import {strings, argPolyfill} from './translations.mjs';
const source = readFileSync(new URL('../AiService.qml', import.meta.url), 'utf8');
const output = vm.createContext({});
vm.runInContext(readFileSync(new URL('../OutputBuffer.js', import.meta.url), 'utf8').replace(/^\.pragma library\s*/, ''), output);
const code = source.slice(source.indexOf('    function command('), source.indexOf('    Timer {'));
function harness() {
  const calls = [], copied = [], pasted = [];
  const host = {
    pluginDir: '/plugin', configDir: '/private', selectionHelper: '/selection.py', selectionSerial: 3,
    busy: false, current: {input:{text:'original'}, context:{canReplace:true, terminal:false, windowAddress:'0x123'}, ctx:{}},
    parseJson: JSON.parse, beginAiResult(){}, updateAiResult(){},
    spawn(spec, done) {
      const buffer = output.create(spec.limit || 65536, spec.lineMode === true);
      const call = {
        spec, cancelled:false, cancel(){this.cancelled=true},
        chunk(data){assert(output.append(buffer, data, spec.onLine));},
        done(result){output.finish(buffer, spec.onLine);done(result);},
      };
      calls.push(call); return call;
    },
    copyText(text, done) {copied.push(text);done(true)},
    queryContext(ctx, done) {done({editable:true, selection:true})},
    pasteCombo(){return {mods:'CTRL',key:'v'}}, sendKeys(keys,address,done){pasted.push(address);done()},
  };
  const c = vm.createContext({host, helper:'/ai.py', config:{version:1,defaultConnection:'ds',connections:[{id:'ds',model:'model'}],buttons:[]},
    strings,
    error:'',saving:false,running:false,active:false,contextValid:true,text:'',status:'',task:null,generation:0,session:null,button:null,selectionSerial:-1,
    flush:{running:false,start(){},stop(){}},settingsWindow:{visible:false}});
  vm.runInContext(argPolyfill,c);
  vm.runInContext(code,c);
  return {c,host,calls,copied,pasted};
}
const action = {id:'translate',title:'Translate',prompt:'{{text}}',output:'preview',connection:''};
function delta(call, text) { call.chunk(JSON.stringify({type:'delta',text}) + '\n'); }
function done(call) { call.chunk('{"type":"done"}\n');call.done({ok:true}); }
test('streams preview without copying and uses a request snapshot',()=>{
  const h=harness(); h.c.run(action);
  assert(h.host.busy);assert(h.c.running);
  const request=JSON.parse(h.calls[0].spec.stdin);
  assert.equal(request.text,'original');assert.equal(request.config.connections[0].model,'model');
  delta(h.calls[0],'你好\n');delta(h.calls[0],'世界');done(h.calls[0]);
  assert.equal(h.c.text,'你好\n世界');assert(!h.c.running);assert(!h.host.busy);assert.deepEqual(h.copied,[]);
  h.c.copy();assert.deepEqual(h.copied,['你好\n世界']);
});
test('cancel stops child and stale chunks/completion cannot change a retry',()=>{
  const h=harness();h.c.run(action);const old=h.calls[0];delta(old,'partial');
  h.c.cancel(false);assert(old.cancelled);assert.equal(h.c.text,'partial');assert(!h.c.running);
  h.c.retry();const next=h.calls[1];delta(next,'new');delta(old,'stale');done(old);
  assert.equal(h.c.text,'new');assert(h.c.running);done(next);assert(!h.c.running);
});
test('failed or incomplete results never perform automatic copy/replace',()=>{
  for(const output of ['copy','replace']) {
    const h=harness();h.c.run({...action,output});delta(h.calls[0],'partial');
    h.calls[0].chunk('{"type":"error","message":"Failed"}\n');h.calls[0].done({ok:false});
    assert.equal(h.c.text,'partial');assert.deepEqual(h.copied,[]);assert.deepEqual(h.pasted,[]);
  }
});
test('replacement rejects changed selections, unknown accessibility and wrong windows',()=>{
  for(const mode of ['serial','context','terminal','window','probe','text']) {
    const h=harness();h.c.run(action);delta(h.calls[0],'answer');done(h.calls[0]);
    if(mode==='serial')h.host.selectionSerial++;
    if(mode==='context')h.c.contextValid=false;
    if(mode==='terminal')h.host.current.context.terminal=true;
    if(mode==='probe')h.host.queryContext=(ctx,done)=>done({editable:true,selection:false});
    h.c.replace();
    if(h.calls[1])h.calls[1].done({ok:true,stdout:JSON.stringify({address:mode==='window'?'0x999':'0x123'})});
    if(h.calls[2])h.calls[2].done({ok:true,stdout:JSON.stringify({ok:true,text:mode==='text'?'changed':'original'})});
    assert.deepEqual(h.pasted,[],mode);assert.deepEqual(h.copied,[],mode);
  }
});
test('replacement needs successful clipboard write and original target',()=>{
  const h=harness();h.c.run(action);delta(h.calls[0],'answer');done(h.calls[0]);h.c.replace();
  h.calls[1].done({ok:true,stdout:'{"address":"0x123"}'});
  h.calls[2].done({ok:true,stdout:'{"ok":true,"text":"original"}'});
  assert.deepEqual(h.copied,['answer']);assert.deepEqual(h.pasted,['0x123']);
});

test('fragmented and batched JSON lines deliver deltas and a final unterminated event',()=>{
  const h=harness();h.c.run(action);const call=h.calls[0];
  call.chunk('{"type":"del');
  assert.equal(h.c.text,'');
  call.chunk('ta","text":"你好"}\n{"type":"delta","text":"世界"}\n{"type":"done"}');
  assert.equal(h.c.text,'你好世界');
  call.done({ok:true});
  assert.equal(h.c.status,'Translate · model');
});
test('provider error reaches the UI instead of the generic incomplete message',()=>{
  const h=harness();h.c.run(action);
  h.calls[0].chunk('{"type":"error","message":"HTTP 401：API Key 无效。"}\n');
  h.calls[0].done({ok:false});
  assert.equal(h.c.status,'HTTP 401：API Key 无效。');
});
