unit Atlas.Common.Lsp.DeepTrees.Tests;

// Läufer außerhalb der Prüfregeln (LSP, Editing) auf sehr tiefen Syntaxbäumen
// (Bericht M1): Sie laufen ohne Rekursion und kommen mit wenig Stapel aus. Die
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
  ChainLength = 5000;
  StackKb = 128;
  /// <summary>Zeile (0-basiert) mit der Kette.</summary>
  ChainLine = 7;

function DeepText: string;
var
  Builder: TStringBuilder;
  Index: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'var'#10'  X: Integer;'#10 +
      'begin'#10'  X := 1');
    for Index := 2 to ChainLength do
      Builder.Append(' - 1');
    Builder.Append(';'#10'  var Y := 2;'#10'  X := Y;'#10'end;'#10'end.'#10);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

procedure TLspDeepTreeTests.WalkersHandleDeepTrees;
var
  Text, Failure, Running, LocalType: string;
  Tree: TSyntaxTree;
  Features, Markers: Integer;
  IsLocal: Boolean;
begin
  Text := DeepText;
  Tree := TPascalParser.Parse(Text);
  try
    Assert.IsTrue(Tree.Depth > ChainLength, 'Kette bleibt linkslastig, Tiefe ' + IntToStr(Tree.Depth));
    Running := '';
    Features := -1;
    Markers := -1;
    IsLocal := False;
    LocalType := '';
    Failure := TSmallStack.Run(StackKb,
      procedure
      begin
        Running := 'TLanguageFeatures.Check';
        Features := Length(TLanguageFeatures.Check(Tree, '19.0'));
        Running := 'TLspInlayHints.EndMarkers';
        Markers := Length(TLspInlayHints.EndMarkers(Tree, TTextRange.Create(0, 0, 100, 0), 1));
        Running := 'TGuardFree.LocalVariableType';
        IsLocal := TGuardFree.LocalVariableType(Tree, Text, 'X', ChainLine, LocalType);
        Running := '';
      end);
  finally
    Tree.Free;
  end;
  Assert.AreEqual('', Failure, Running);
  // Delphi 10.2 kennt keine Inline-Variable: var Y meldet sich.
  Assert.AreEqual(1, Features, 'Sprachmerkmale');
  Assert.IsTrue(Markers >= 0, 'Endmarken');
  Assert.IsTrue(IsLocal, 'X ist lokal');
  Assert.AreEqual('Integer', LocalType);
  Text := '';
  Failure := '';
  Running := '';
  LocalType := '';
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDeepTreeTests);

end.
