unit Atlas.Common.Lsp.DeepTrees.Tests;

// Läufer außerhalb der Prüfregeln (LSP, Editing) auf sehr tiefen Syntaxbäumen
//: Sie laufen ohne Rekursion und kommen mit wenig Stapel aus. Die
// Kette 1 - 1 - … - 1 baut der Parser linkslastig, der Baum ist so tief wie
// die Kette lang.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspDeepTreeTests = class
  public
    /// <summary>Sprachmerkmale, Endmarken und lokaler Typ in einer Unit mit 5000 Gliedern in 128 KB Stapel.
    /// </summary>
    [Test]
    procedure WalkersHandleDeepTrees;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Lsp.InlayHints,
  Atlas.Common.Editing.GuardFree,
  Atlas.Tests.SmallStack;

const
  cChainLength = 5000;
  cStackKb = 128;
  /// <summary>Zeile (0-basiert) mit der Kette.</summary>
  cChainLine = 7;

function DeepText: string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'var'#10'  X: Integer;'#10 +
      'begin'#10'  X := 1');
    for mIndex := 2 to cChainLength do
    begin
      mBuilder.Append(' - 1');
    end;
    mBuilder.Append(';'#10'  var Y := 2;'#10'  X := Y;'#10'end;'#10'end.'#10);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

procedure TLspDeepTreeTests.WalkersHandleDeepTrees;
var
  mText, mFailure, mRunning, mLocalType: string;
  mTree: TSyntaxTree;
  mFeatures, mMarkers: Integer;
  mIsLocal: Boolean;
begin
  mText := DeepText;
  mTree := TPascalParser.Parse(mText);
  try
    Assert.IsTrue(mTree.Depth > cChainLength, 'Kette bleibt linkslastig, Tiefe ' + IntToStr(mTree.Depth));
    mRunning := '';
    mFeatures := -1;
    mMarkers := -1;
    mIsLocal := False;
    mLocalType := '';
    mFailure := TSmallStack.Run(cStackKb,
      procedure
      begin
        mRunning := 'TLanguageFeatures.Check';
        mFeatures := Length(TLanguageFeatures.Check(mTree, '19.0'));
        mRunning := 'TLspInlayHints.EndMarkers';
        mMarkers := Length(TLspInlayHints.EndMarkers(mTree, TTextRange.Create(0, 0, 100, 0), 1));
        mRunning := 'TGuardFree.LocalVariableType';
        mIsLocal := TGuardFree.LocalVariableType(mTree, mText, 'X', cChainLine, mLocalType);
        mRunning := '';
      end);
  finally
    mTree.Free;
  end;
  Assert.AreEqual('', mFailure, mRunning);
  // Delphi 10.2 kennt keine Inline-Variable: var Y meldet sich.
  Assert.AreEqual(1, mFeatures, 'Sprachmerkmale');
  Assert.IsTrue(mMarkers >= 0, 'Endmarken');
  Assert.IsTrue(mIsLocal, 'X ist lokal');
  Assert.AreEqual('Integer', mLocalType);
  mText := '';
  mFailure := '';
  mRunning := '';
  mLocalType := '';
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDeepTreeTests);

end.
