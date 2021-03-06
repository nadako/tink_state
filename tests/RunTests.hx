package ;

class RunTests {

  static function main() {
    tink.testrunner.Runner.run(tink.unit.TestBatch.make([
      new TestBasic(),
      new TestDate(),
      new TestAuto(),
      new TestMaps(),
      new TestArrays(),
      new TestScheduler(),
      new TestProgress(),
    ]))
      .handle(function(result) {
        travix.Logger.exit(result.summary().failures.length);
      });
  }
}