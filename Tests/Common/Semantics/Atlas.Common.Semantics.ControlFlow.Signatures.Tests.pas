unit Atlas.Common.Semantics.ControlFlow.Signatures.Tests;

// Übergabeart der Argumente für den Kontrollfluss (#143): Standardroutinen, Routinen derselben Datei
// (var, out, Wert), Überladungen mit verschiedener Art bleiben unbekannt, Aufrufe über Objekte ebenso;
// dazu die noreturn-Liste der Routinenköpfe.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFlowSignaturesTests = class
  public
    [Test]
    procedure BuiltinRoutinesKnowTheirModes;
    [Test]
    procedure UnknownNameIsNoBuiltin;
    [Test]
    procedure TreeRoutinesGiveModesPerArgument;
    [Test]
    procedure NoReturnVerdictsListEveryHeader;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Semantics.ControlFlow.Signatures;

const
  LB = #13#10;
  ModeNames: array[TFlowArgumentMode] of string = ('value', 'ref', 'out', '?');

  UnitCalls =
    'unit Haupt;' + LB +
    'interface' + LB +
    'implementation' + LB +
    'procedure Take(var A: Integer; out B: Integer; C, D: Integer);' + LB +
    'begin' + LB +
    'end;' + LB +
    'procedure Twice(A: Integer); overload;' + LB +
    'begin' + LB +
    'end;' + LB +
    'procedure Twice(var A: string); overload;' + LB +
    'begin' + LB +
    'end;' + LB +
    'procedure Run(AList: TObject);' + LB +
    'var X, Y: Integer; S: string;' + LB +
    'begin' + LB +
    '  Take(X, Y, 1, 2);' + LB +
    '  Twice(S);' + LB +
    '  AList.Take(X);' + LB +
    '  SetLength(S, 3);' + LB +
    '  Fremd(X);' + LB +
    'end;' + LB +
    'end.';

  UnitNoReturn =
    'unit Ende;' + LB +
    'interface' + LB +
    'type' + LB +
    '  TStopper = class' + LB +
    '    procedure Halt2; noreturn;' + LB +
    '  end;' + LB +
    'procedure Fail(const AText: string); noreturn;' + LB +
    'implementation' + LB +
    'procedure Fail(const AText: string);' + LB +
    'begin' + LB +
    'end;' + LB +
    'procedure TStopper.Halt2;' + LB +
    'begin' + LB +
    'end;' + LB +
    'end.';

function ModeOf(const AName: string; AArgument: Integer): string;
var
  mMode: TFlowArgumentMode;
begin
  if TFlowSignatures.TryBuiltin(AName, AArgument, mMode) then
  begin
    Result := ModeNames[mMode];
  end
  else
  begin
    Result := '-';
  end;
end;

/// <summary>Übergabearten aller Argumente aller Aufrufe als "Name:Art,Art", mit Leerzeichen getrennt.</summary>
function CallModes(ATree: TSyntaxTree): string;
var
  mLookup: TFlowSignatureLookup;
  mCalls: TList<TSyntaxNode>;
  mCall: TSyntaxNode;
  mItem: string;
  mArgument: Integer;
begin
  Result := '';
  mCalls := TList<TSyntaxNode>.Create;
  try
    mLookup := TFlowSignatures.FromTree(ATree.Root);
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if ANode.Kind = TSyntaxKind.Call then
        begin
          mCalls.Add(ANode);
        end;
        Result := True;
      end);
    for mCall in mCalls do
    begin
      mItem := mCall.Name + ':';
      for mArgument := 0 to mCall.ChildCount - 2 do
      begin
        if mArgument > 0 then
        begin
          mItem := mItem + ',';
        end;
        mItem := mItem + ModeNames[mLookup(mCall, mArgument)];
      end;
      if Result <> '' then
      begin
        Result := Result + ' ';
      end;
      Result := Result + mItem;
    end;
  finally
    mLookup := nil;
    mCalls.Free;
  end;
end;

procedure TFlowSignaturesTests.BuiltinRoutinesKnowTheirModes;
begin
  Assert.AreEqual('ref', ModeOf('SetLength', 0));
  Assert.AreEqual('value', ModeOf('SetLength', 1));
  // Das letzte Zeichen gilt für alle weiteren Argumente.
  Assert.AreEqual('value', ModeOf('setlength', 5));
  Assert.AreEqual('out', ModeOf('Str', 1));
  Assert.AreEqual('ref', ModeOf('FreeAndNil', 0));
  Assert.AreEqual('value', ModeOf('Length', 0));
  Assert.AreEqual('value', ModeOf('Integer', 0));
end;

procedure TFlowSignaturesTests.UnknownNameIsNoBuiltin;
var
  mMode: TFlowArgumentMode;
begin
  Assert.IsFalse(TFlowSignatures.TryBuiltin('Fremd', 0, mMode));
  Assert.AreEqual('?', ModeNames[mMode]);
end;

procedure TFlowSignaturesTests.TreeRoutinesGiveModesPerArgument;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(UnitCalls);
  try
    // Take aus der Datei (C, D in einer Gruppe), Twice mit verschiedenen Überladungen unbekannt, Methode über
    // ein Objekt unbekannt, SetLength aus der Tabelle, Fremd ohne Kopf unbekannt.
    Assert.AreEqual('Take:ref,out,value,value Twice:? Take:? SetLength:ref,value Fremd:?', CallModes(mTree));
  finally
    mTree.Free;
  end;
end;

procedure TFlowSignaturesTests.NoReturnVerdictsListEveryHeader;
var
  mTree: TSyntaxTree;
  mVerdict: TPair<string, Boolean>;
  mItems: TArray<string>;
begin
  mItems := nil;
  mTree := TPascalParser.Parse(UnitNoReturn);
  try
    for mVerdict in TFlowSignatures.NoReturnVerdicts(mTree.Root) do
    begin
      if mVerdict.Value then
      begin
        mItems := mItems + [mVerdict.Key + '=noreturn'];
      end
      else
      begin
        mItems := mItems + [mVerdict.Key];
      end;
    end;
  finally
    mTree.Free;
  end;
  TArray.Sort<string>(mItems);
  // Je Kopf ein Eintrag, ohne Klassennamen und klein; noreturn steht nur an der Deklaration.
  Assert.AreEqual('fail,fail=noreturn,halt2,halt2=noreturn', string.Join(',', mItems));
  Assert.AreEqual(0, Integer(Length(TFlowSignatures.NoReturnVerdicts(nil))));
end;

initialization
  TDUnitX.RegisterTestFixture(TFlowSignaturesTests);

end.
