import {classifyAction} from "../../../src/shared/audit/classifyAction";

describe("classifyAction", () => {
  it("returns create when there is no before state", () => {
    expect(classifyAction(null, {title: "New"})).toBe("create");
  });

  it("returns delete when there is no after state", () => {
    expect(classifyAction({title: "Old"}, null)).toBe("delete");
  });

  it("returns soft_delete when isDeleted flips false -> true", () => {
    expect(classifyAction({isDeleted: false}, {isDeleted: true})).toBe("soft_delete");
  });

  it("returns restore when isDeleted flips true -> false", () => {
    expect(classifyAction({isDeleted: true}, {isDeleted: false})).toBe("restore");
  });

  it("returns update for an ordinary field change", () => {
    expect(classifyAction({title: "Old"}, {title: "New"})).toBe("update");
  });
});
