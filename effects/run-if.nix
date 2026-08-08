# When the condition is false we still want eval/build of the effect's
# closure to succeed, so return a no-op effect instead.
condition: effect:
if condition then
  { run = effect; }
else
  {
    dependencies = effect.inputDerivation // {
      isEffect = false;
      buildDependenciesOnly = true;
    };
  }
