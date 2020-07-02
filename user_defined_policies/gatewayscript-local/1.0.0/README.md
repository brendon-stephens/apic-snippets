# Local GatewayScript
This user defined policy allows for developers to reference GatewayScript policies which are stored on the DataPower appliances. This is useful for sharing common code which you do not want to embed within the API assembly. The policy supports passing of custom parameters to the script.

## Installation
1. Upload the gatewayscript-local.schema.json file to local:///ondisk/framework/gatewayscript-local/1.0.0
2. Import the gatewayscript-local.xcfg file on to the DataPower appliance.
3. Add gatewayscript-local as a user-defined policy in the API Connect Gateway Service configuration.

## Usage
To call the file you add the following policy to your API assembly:

```yaml
assembly:
  execute:
    - gatewayscript-local:
        version: 1.0.0
        title: gatewayscript-local
        parameters:
          - name: 'message'
            value: 'HelloWorld!'
        file: 'local:///ondisk/gatewayscript/helloworld.js'
```

Note that the GatewayScript file must be deployed to all appliances which the API is deployed to. 

helloworld.js
```javascript
const utils = require('local:///ondisk/framework/utilities.js');
let message = utils.getScriptParameter(context, 'message');

context.message.header.set('Content-Type', 'application/json');
context.message.body.write({ message });
```

utilities.js
```javascript
module.exports = {
    /**
     * Returns a parameter value from the array of parameters passed
     * into the gatewayscript-local and xslt-local user defined 
     * assembly policies. Returns undefined if no result is found.
     * 
     * @param {object} context the api context object
     * @param {string} search the parameter name to retrieve
     * 
     * @return the parameter value, or undefined if not found.
     */
    getScriptParameter: (context, search) => {
        // policyParams are parameters which have been defined as 
        // part of the custom gatewayscript-local and xslt-local 
        // assembly policies.
        const policyParams = context.get('local.parameter');
        // scriptParams is the 'parameters' parameter which was 
        // defined as part of the custom assembly policies. It is an 
        // array of objects containing name/value pairs.
        const scriptParams = JSON.parse(policyParams.parameters || []);
        
        let obj = scriptParams.find((p) => {
            return p.name.toLowerCase() === search.toLowerCase();
        });

        return obj != undefined ? obj.value : undefined;
    }
}
```
