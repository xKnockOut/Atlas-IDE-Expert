unit Atlas.Common.Semantics.RtlMethodReferences.Tests;

// Methodenreferenzen aus System.SysUtils ohne Quelltext der RTL (#468, #2309): Typargumente zerlegen,
// Deklarationen wie in der RTL, Bindungen der Typparameter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRtlMethodReferencesTests = class
  public
    [Test]
    procedure SplitsTypeArgs;
    [Test]
    procedure Declarations;
    /// <summary>#2309: TProc&lt;string&gt; mit Bindung T=string, TFunc mit TResult, andere Namen und Zahlen
    /// nicht.</summary>
    [Test]
    procedure FindsWithBindings;
    [Test]
    procedure RecognizesSysUtils;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Semantics.RtlMethodReferences;

procedure TRtlMethodReferencesTests.SplitsTypeArgs;
var
  mBase: string;
begin
  Assert.AreEqual('TCustomer|TFunc<Integer, string>', string.Join('|',
    TRtlMethodReferences.TypeArgs('TFunc<TCustomer, TFunc<Integer, string>>', mBase)));
  Assert.AreEqual('TFunc', mBase);
  Assert.AreEqual(0, Integer(Length(TRtlMethodReferences.TypeArgs('System.SysUtils.TProc', mBase))));
  Assert.AreEqual('System.SysUtils.TProc', mBase);
end;

procedure TRtlMethodReferencesTests.Declarations;
begin
  Assert.AreEqual('TProc = reference to procedure;', TRtlMethodReferences.Declaration('TProc', 0));
  Assert.AreEqual('TProc<T> = reference to procedure(Arg1: T);',
    TRtlMethodReferences.Declaration('System.SysUtils.TProc', 1));
  Assert.AreEqual('TProc<T1, T2> = reference to procedure(Arg1: T1; Arg2: T2);',
    TRtlMethodReferences.Declaration('TProc', 2));
  Assert.AreEqual('TFunc<TResult> = reference to function: TResult;', TRtlMethodReferences.Declaration('TFunc', 1));
  Assert.AreEqual('TFunc<T, TResult> = reference to function(Arg1: T): TResult;',
    TRtlMethodReferences.Declaration('SysUtils.TFunc', 2));
  Assert.AreEqual('TPredicate<T> = reference to function(Arg1: T): Boolean;',
    TRtlMethodReferences.Declaration('TPredicate', 1));
  Assert.AreEqual('', TRtlMethodReferences.Declaration('TFunc', 0));
  Assert.AreEqual('', TRtlMethodReferences.Declaration('TProc', 5));
  Assert.AreEqual('', TRtlMethodReferences.Declaration('TPredicate', 2));
  Assert.AreEqual('', TRtlMethodReferences.Declaration('TList', 1));
end;

procedure TRtlMethodReferencesTests.FindsWithBindings;
var
  mReference: TRtlMethodReference;
begin
  Assert.IsTrue(TRtlMethodReferences.Find('TProc<string>', mReference));
  Assert.AreEqual('TProc', mReference.Name);
  Assert.AreEqual('TProc<T> = reference to procedure(Arg1: T);', mReference.Signature);
  Assert.AreEqual('T=string', string.Join('|', mReference.Bindings));
  Assert.IsTrue(TRtlMethodReferences.Find('System.SysUtils.TFunc<Integer, TArray<string>>', mReference));
  Assert.AreEqual('TFunc', mReference.Name);
  Assert.AreEqual('T=Integer|TResult=TArray<string>', string.Join('|', mReference.Bindings));
  Assert.IsTrue(TRtlMethodReferences.Find('TProc', mReference));
  Assert.AreEqual(0, Integer(Length(mReference.Bindings)));
  Assert.IsFalse(TRtlMethodReferences.Find('TFunc', mReference));
  Assert.IsFalse(TRtlMethodReferences.Find('TList<string>', mReference));
  Assert.IsFalse(TRtlMethodReferences.Find('TProc<A, B, C, D, E>', mReference));
end;

procedure TRtlMethodReferencesTests.RecognizesSysUtils;
begin
  Assert.IsTrue(TRtlMethodReferences.IsSysUtils('System.SysUtils'));
  Assert.IsTrue(TRtlMethodReferences.IsSysUtils('sysutils'));
  Assert.IsFalse(TRtlMethodReferences.IsSysUtils('System.Classes'));
end;

initialization
  TDUnitX.RegisterTestFixture(TRtlMethodReferencesTests);

end.
