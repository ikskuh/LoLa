
const templates = [
  {
    name: 'Hello, World!',
    text: 'Print("Hello, World!");',
  },
];

var terminal;
var editor;

function loadTemplate(id) {
  editor.session.setValue(templates[id].text);
}
const utf8_enc = new TextEncoder('utf-8');
const utf8_dec = new TextDecoder('utf-8');

function validateCode() {
  const code = editor.session.getValue();

  var encoded_text = utf8_enc.encode(code);

  const string_ptr = wasmContext.instance.exports.malloc(encoded_text.length);

  let byteView = new Uint8Array(
      wasmContext.instance.exports.memory.buffer, string_ptr,
      encoded_text.length);

  let i = 0;
  while (i < encoded_text.length) {
    byteView[i] = encoded_text[i];
    i += 1;
  }

  const result =
      wasmContext.instance.exports.validate(string_ptr, encoded_text.length);

  wasmContext.instance.exports.free(string_ptr, encoded_text.length);

  if (result != 0) console.log('failed to validate code!');
}

function runCode() {
  const code = editor.session.getValue();

  var encoded_text = utf8_enc.encode(code);

  const string_ptr = wasmContext.instance.exports.malloc(encoded_text.length);

  let byteView = new Uint8Array(
      wasmContext.instance.exports.memory.buffer, string_ptr,
      encoded_text.length);

  let i = 0;
  while (i < encoded_text.length) {
    byteView[i] = encoded_text[i];
    i += 1;
  }

  if (!wasmContext.instance.exports.isInterpreterDone()) {
    wasmContext.instance.exports.deinitInterpreter();
  }

  const result = wasmContext.instance.exports.initInterpreter(
      string_ptr, encoded_text.length);
  wasmContext.instance.exports.free(string_ptr, encoded_text.length);

  if (result != 0) {
    console.log('failed to compile code!');
  } else {
    // kick off interpreter loop
    terminal.clear();
    wasmContext.start_time = Date.now();
    window.requestAnimationFrame(stepRuntime);
  }
}

function showHelp() {
  window.open('docs/language.htm', '_blank');
}

// run this when the site is fully loaded
window.addEventListener('DOMContentLoaded', (ev) => {
  // Initialize editor
  editor = ace.edit('editor');
  // editor.setTheme("ace/theme/vibrant_ink");
  editor.session.setMode('ace/mode/javascript');

  // Initialize terminal
  {
    terminal = new Terminal();
    const fitAddon = new FitAddon.FitAddon();
    terminal.loadAddon(fitAddon);
    terminal.open(document.getElementById('output'));
    fitAddon.fit();
  }


  // Initialize samples dropdown
  {
    const examples = document.getElementById('examples');

    examples.options.length = 0;
    for (const index in templates) {
      examples.options.add(new Option(templates[index].name, String(index)));
    }
    loadTemplate(0);
  }
});



var wasmContext = {
  instance: null,
  inputBuffer: '',
  start_time: 0,
};

const wasmImports = {
  env: {
    compileLog: (data, len) => {
      let byteView =
          new Uint8Array(wasmContext.instance.exports.memory.buffer, data, len);

      let s = utf8_dec.decode(byteView);

      terminal.write(s);
    },
    millis: () => {
      return Date.now() - wasmContext.start_time;
    },
  }
};

function translateEmulatorError(ind) {
  switch (ind) {
    case 0:
      return 'success';
    default:
      return 'unknown';
  }
}

function stepRuntime(time) {
  if (!wasmContext.instance.exports.isInterpreterDone()) {
    const success = wasmContext.instance.exports.stepInterpreter(100000);
    if (success == 0) {
      // continue
      window.requestAnimationFrame(stepRuntime);
    } else {
      console.log(success);
      alert('emulator failed: ' + translateEmulatorError(success));
    }
  }
}


// Load and initialize the wasm runtime
fetch('lola.wasm')
    .then(response => response.arrayBuffer())
    .then(bytes => WebAssembly.instantiate(bytes, wasmImports))
    .then(results => {
      wasmContext.instance = results.instance;

      // this initialize the allocator and such
      results.instance.exports.initialize();
    });

templates.push({
  name: 'Bubblesort',
  text: `function BubbleSort(const_arr)
{
  var arr = const_arr;
  var len = Length(arr);

  var n = len;
  while(n > 1) {

    var i = 0;
    while(i < n - 1) {
      if (arr[i] > arr[i+1]) {
        var tmp = arr[i];
        arr[i] = arr[i+1];
        arr[i+1] = tmp;
      }

      i += 1;
    }
    n -= 1;
  }

  return arr;
}

// Sorting works on numbers
Print(BubbleSort([ 7, 8, 9, 3, 2, 1 ]));

// as well as strings
Print(BubbleSort([
  "scorn",
  "by nature",
  "Agave cantala",
  "solvophobic",
  "outpost",
  "ovotestis",
  "weather",
  "ablation",
  "boresighting",
  "postfix"
]));`,
});

templates.push({
  name: 'Simple Timer',
  text: `while(true) {
  Print(Timestamp());
  Yield();
}`
});