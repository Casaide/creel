const createTestnet = require('hyperdht/testnet')
createTestnet(3, { host: '127.0.0.1' }).then(t => { console.log(t.bootstrap.map(b => b.host + ':' + b.port).join(',')) })
