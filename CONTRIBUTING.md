## Contributing
Below is a list of basic guidelines to follow when writing code you'd like to be merged into UCBG:

* Use the StyLua formatter. If you're using VSCode, you can find the extension [here](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.stylua). For more information on StyLua, see [StyLua](https://github.com/JohnnyMorganz/StyLua).
* Use size-4 indentation, with TAB characters, not spaces.
* All functions should be `local`, and named in [PascalCase](https://www.freecodecamp.org/news/snake-case-vs-camel-case-vs-pascal-case-vs-kebab-case-whats-the-difference/).
* All variables should be named in [camelCase](https://www.freecodecamp.org/news/snake-case-vs-camel-case-vs-pascal-case-vs-kebab-case-whats-the-difference/).
* Types should be named in PascalCase, i.e. `export type BlockDef`.
* "Class" tables should be named in PascalCase, i.e. `local Block = {}`.
* Class properties should be named in PascalCase, i.e. `BlockDef.BindShifted`.

###### Note: My styling isn't perfectly consistent, so if you notice an error with these in the source code, make an Issue about it and I'll fix it, or a PR if you want to fix it yourself. If you need more clarification on something I might not have listed here, let me know in the Discord server, or make an Issue.
