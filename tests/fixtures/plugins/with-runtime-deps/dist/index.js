import leftPad from "left-pad";

export default {
  name: "fixture-with-runtime-deps",
  render(value) {
    return leftPad(String(value), 4, "0");
  },
};
