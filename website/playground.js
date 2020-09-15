
const templates = [
  {
    name: 'Hello, World!',
    text: 'Print("Hello, World!");',
  },
];



function loadTemplate(id) {
  editor.session.setValue(templates[id].text);
}

function validateCode() {
  const code = editor.session.getValue();

  console.log('validate', code);
}

function runCode() {
  const code = editor.session.getValue();

  console.log('run', code);
}

function showHelp() {
  window.open('docs/language.htm', '_blank');
}

// run this when the site is fully loaded
window.addEventListener('DOMContentLoaded', (ev) => {
  const examples = document.getElementById('examples');

  examples.options.length = 0;
  for (const index in templates) {
    examples.options.add(new Option(templates[index].name, String(index)));
  }
  loadTemplate(0);

  console.log();
});



var wasmContext = {
  instance: null,
  inputBuffer: '',
  is_running: false,
};

const wasmImports = {
  env: {
      // serialRead: (data, len) => {
      //   let byteView =
      //       new Uint8Array(wasmContext.instance.exports.memory.buffer, data,
      //       len);

      //   let i = 0;
      //   while (wasmContext.inputBuffer.length > 0 && i < len) {
      //     const c = wasmContext.inputBuffer.charCodeAt(0);

      //     byteView[i] = c;

      //     i += 1;
      //     wasmContext.inputBuffer = wasmContext.inputBuffer.substr(1);
      //   }

      //   return i;
      // },
      // serialWrite: (data, len) => {
      //   const decoder = new TextDecoder('utf-8');

      //   let byteView =
      //       new Uint8Array(wasmContext.instance.exports.memory.buffer, data,
      //       len);

      //   let s = decoder.decode(byteView);

      //   term.write(s);
      // }
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
  if (wasmContext.is_running) {
    // validate
    // initInterpreter
    // deinitInterpreter
    // stepInterpreter

    const success = wasmContext.instance.exports.run(4096);
    if (success == 0) {
      // continue
      window.requestAnimationFrame(stepRuntime);
    } else {
      alert('emulator failed: ', translateEmulatorError(success));
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

      window.requestAnimationFrame(stepRuntime);
    });

templates.push({
  name: 'Bubblesort',
  text: `function BubbleSort(arr)
{
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