// Wire-aware opt-in marker. This module declares no bindings — it is the domain: `TaskItem`,
// `TaskStatus`, and the `TaskRepository` protocol. The marker is here because `TaskController` is
// *generic over* `TaskRepository`, and the conformer WireOpenAPIGen emits into the executable has to
// name that constraint. The emitted file imports each Wire-aware dependency, so without this the
// generated code says `cannot find type 'TaskRepository' in scope`.
