
const templates = [
  {
    name: 'Hello, World!',
    text:
        `// Enter LoLa code here and press [Run] above to compile & execute the code!
Print("Hello, World!");
`,
  },
];

var terminal;
var editor;


var concatArrayBuffers = function(buffer1, buffer2) {
  var tmp = new Uint8Array(buffer1.length + buffer2.length);
  tmp.set(buffer1, 0);
  tmp.set(buffer2, buffer1.length);
  return tmp;
};

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

function stopCode() {
  wasmContext.instance.exports.deinitInterpreter();
  document.getElementById('stopButton').classList.add('hidden');
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
    stopCode();
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
    wasmContext.input_buffer = new Uint8Array();
    document.getElementById('stopButton').classList.remove('hidden');
    window.requestAnimationFrame(stepRuntime);

    terminal.focus();
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

  terminal.write(`Your program output will appear here!\r\n`);

  terminal.onData(data => {
    if (!wasmContext.instance.exports.isInterpreterDone()) {
      wasmContext.input_buffer = concatArrayBuffers(
          wasmContext.input_buffer,
          utf8_enc.encode(data),
      );
    }
  });

  // Initialize samples dropdown
  {
    const examples = document.getElementById('examples');

    examples.options.length = 0;
    for (const index in templates) {
      examples.options.add(new Option(templates[index].name, String(index)));
    }
  }

  editor.session.setValue(
      `// Enter LoLa code here and press [Run] above to compile & execute the code!
Print("Hello, World!");
while(true) {
  var str = Read();
  if(str != "")
    Write("[", str, "]");
}

// Available functions are:
// - All of the standard library (see [Help])
// - "Print(…): void" Prints all arguments, then writes a new line
// - "Write(…): void" Prints all arguments without appending a new line
// - "Read(): string" Reads all available text from the terminal.
`);
});



var wasmContext = {
  instance: null,
  input_buffer: new Uint8Array(),
  start_time: 0,
};

const wasmImports = {
  env: {
    readString: (data, len) => {
      let target_buffer = new Uint8Array(
          wasmContext.instance.exports.memory.buffer,
          data,
          len,
      );

      let actual_len = Math.min(wasmContext.input_buffer.length, len);

      for (var i = 0; i < actual_len; i++) {
        target_buffer[i] = wasmContext.input_buffer[i];
      }

      wasmContext.input_buffer = wasmContext.input_buffer.slice(actual_len);

      return i;
    },
    writeString: (data, len) => {
      let source_buffer = new Uint8Array(
          wasmContext.instance.exports.memory.buffer,
          data,
          len,
      );

      let s = utf8_dec.decode(source_buffer);

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
    case 1:
      return 'out of memory';
    case 2:
      return 'compilation error';
    case 3:
      return 'compilation error';
    case 4:
      return 'panic';
    case 5:
      return 'invalid object';
    case 6:
      return 'invalid interpreter state';
    default:
      return 'unknown';
  }
}

function stepRuntime(time) {
  if (!wasmContext.instance.exports.isInterpreterDone()) {
    const success = wasmContext.instance.exports.stepInterpreter(1000);

    if (wasmContext.instance.exports.isInterpreterDone()) {
      document.getElementById('stopButton').classList.add('hidden');
    }

    if (success == 0) {
      // continue
      window.requestAnimationFrame(stepRuntime);
    } else if (success == 4) {
      // that's a panic, we just use the message printed from within the VM
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

templates.push({
  name: 'Stack Trace',
  text: `function Nested() {
    Boom();
}

function Deeply() {
    Nested();
}

function Within() {
    Deeply();
}

Within();`
});