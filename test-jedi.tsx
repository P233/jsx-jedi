import React, { useState } from "react"; // import_statement, named_imports

// --- Types & Interfaces ---

// type_alias_declaration
type ID = string | number;

// tuple_type
type Point = [number, number];

// interface_declaration
interface UserProps {
  id: ID;
  name: string;
  isActive: boolean;
}

// --- Variables & Assignments ---

// lexical_declaration, variable_declarator
let count = 0;
var count = 0;
const MAX_COUNT = 10;

// assignment_expression
count = 1;

// array_pattern (destructuring)
const [x, y] = [1, 2];

// object_pattern (destructuring)
const { debug } = { debug: true };

// --- Functions ---

// function_declaration, formal_parameters
function add(a: number, b: number = 0) {
  // return_statement
  return a + b;
}

// arrow_function
const multiply = (a: number, b: number) => a * b;

// arguments (function call)
add(1, 2);

// --- Classes ---

// class_declaration
class Counter {
  // method_definition
  increment() {
    count++;
  }
}

// --- Control Flow ---

function controlFlow(val: any) {
  // if_statement, statement_block
  if (val) {
    console.log("True");
  }

  // switch_statement
  switch (val) {
    case 1:
      break;
  }

  // try_statement
  try {
    // throw_statement
    throw new Error("Oops");
  } catch (e) {
    console.error(e);
  }
}

// --- Loops ---

function loops(arr: any[], obj: any) {
  // for_statement
  for (let i = 0; i < 10; i++) {}

  // for_in_statement
  for (const key in obj) {
  }

  // while_statement
  while (true) {
    break;
  }

  // do_statement
  do {
    break;
  } while (true);
}

// --- Data Structures ---

// object
const config = {
  // pair
  key: "value",
  // string
  name: "Jedi",
  // template_string
  desc: `Master ${"Yoda"}`,
  // array
  list: [1, 2, 3],
};

// --- Expressions ---

// expression_statement
console.log("Hello");

// parenthesized_expression
const calc = (1 + 2) * 3;

// --- JSX ---

function Component() {
  return (
    // jsx_element, jsx_opening_element
    <div className="container" /* jsx_attribute */>
      {/* comment (inside JSX) */}

      {/* jsx_expression */}
      {count > 0 && (
        // jsx_self_closing_element
        <input type="text" />
      )}
    </div>
  );
}

// --- Exports ---

// export_statement
export const version = "1.0";

// export_clause
export { add, multiply };
