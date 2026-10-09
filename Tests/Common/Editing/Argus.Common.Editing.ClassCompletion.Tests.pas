unit Argus.Common.Editing.ClassCompletion.Tests;

interface

uses
  DUnitX.TestFramework,
  Argus.Common.Editing.CodeActions;

type
  [TestFixture]
  TClassCompletionTests = class
  private
    function ActionAt(const AText: string; ALine: Integer; out AAction: TCodeAction): Boolean;
    function Apply(const AText: string; const AAction: TCodeAction): string;
  public
    [Test]
    procedure AddsSingleMissingBody;
    [Test]
    procedure AddsAllMissingBodiesOfType;
    [Test]
    procedure InsertsAfterLastMethodOfType;
    [Test]
    procedure KeepsFunctionsAndClassMethods;
    [Test]
    procedure SkipsImplementedAndAbstractMethods;
    [Test]
    procedure MatchesOverloadsByParameters;
    [Test]
    procedure NothingOutsideTypes;
  end;

implementation

uses
  System.SysUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser,
  Argus.Common.Editing.ClassCompletion;

const
  Leer =
    'unit U;'#10 +                                  // 0
    'interface'#10 +                                // 1
    'type'#10 +                                     // 2
    '  TFoo = class'#10 +                           // 3
    '    procedure Lauf(A: Integer);'#10 +          // 4
    '    function Wert: string; virtual;'#10 +      // 5
    '  end;'#10 +                                   // 6
    'implementation'#10 +                           // 7
    #10 +                                           // 8
    'end.';                                         // 9

{ TClassCompletionTests }

function TClassCompletionTests.ActionAt(const AText: string; ALine: Integer; out AAction: TCodeAction): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TClassCompletion.MissingBodies(Tree, AText, TTextPosition.Create(ALine, 6), AAction);
  finally
    Tree.Free;
  end;
end;

function TClassCompletionTests.Apply(const AText: string; const AAction: TCodeAction): string;
var
  Lines: TArray<string>;
  Edit: TRuleEdit;
  Line: string;
begin
  // Genau eine Einfügung.
  Assert.AreEqual(1, Integer(Length(AAction.Edits)));
  Edit := AAction.Edits[0];
  Lines := AText.Split([#10]);
  Line := Lines[Edit.Range.StartPos.Line];
  Lines[Edit.Range.StartPos.Line] := Copy(Line, 1, Edit.Range.StartPos.Character) + Edit.NewText +
    Copy(Line, Edit.Range.EndPos.Character + 1, MaxInt);
  Result := string.Join(#10, Lines);
end;

procedure TClassCompletionTests.AddsSingleMissingBody;
var
  Action: TCodeAction;
begin
  Assert.IsTrue(ActionAt(Leer, 4, Action));
  Assert.AreEqual('Methodenrumpf für TFoo.Lauf erzeugen', Action.Title);
  Assert.AreEqual(RewriteKind, Action.Kind);
  Assert.AreEqual(
    'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'    procedure Lauf(A: Integer);'#10 +
    '    function Wert: string; virtual;'#10'  end;'#10'implementation'#10#10 +
    'procedure TFoo.Lauf(A: Integer);'#10'begin'#10#10'end;'#10#10'end.',
    Apply(Leer, Action));
end;

procedure TClassCompletionTests.AddsAllMissingBodiesOfType;
var
  Action: TCodeAction;
  Text: string;
begin
  // Cursor auf der Typzeile: alle fehlenden Rümpfe.
  Assert.IsTrue(ActionAt(Leer, 3, Action));
  Assert.AreEqual('2 fehlende Methodenrümpfe für TFoo erzeugen', Action.Title);
  Text := Apply(Leer, Action);
  Assert.Contains(Text, 'procedure TFoo.Lauf(A: Integer);'#10'begin'#10#10'end;'#10#10 +
    'function TFoo.Wert: string;'#10'begin'#10#10'end;'#10#10'end.');
end;

procedure TClassCompletionTests.InsertsAfterLastMethodOfType;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    procedure Eins;'#10 +
    '    procedure Zwei;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Eins;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Frei;'#10 +
    'begin'#10 +
    'end;'#10 +
    'initialization'#10 +
    'end.';
var
  Action: TCodeAction;
begin
  Assert.IsTrue(ActionAt(Text, 5, Action));
  Assert.Contains(Apply(Text, Action),
    'procedure TFoo.Eins;'#10'begin'#10'end;'#10#10'procedure TFoo.Zwei;'#10'begin'#10#10'end;'#10'procedure Frei;');
end;

procedure TClassCompletionTests.KeepsFunctionsAndClassMethods;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    class function Neu(const A: string;'#10 +
    '      B: Integer): TFoo; static;'#10 +
    '    constructor Create;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';
var
  Action: TCodeAction;
  Applied: string;
begin
  Assert.IsTrue(ActionAt(Text, 3, Action));
  Applied := Apply(Text, Action);
  Assert.Contains(Applied, 'class function TFoo.Neu(const A: string; B: Integer): TFoo;'#10'begin');
  Assert.Contains(Applied, 'constructor TFoo.Create;'#10'begin');
  // Direktiven wie static gehören nicht in die Implementierung.
  Assert.IsFalse(Action.Edits[0].NewText.Contains('static'));
end;

procedure TClassCompletionTests.SkipsImplementedAndAbstractMethods;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    procedure Fertig;'#10 +
    '    procedure Leer; virtual; abstract;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Fertig;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
var
  Action: TCodeAction;
begin
  Assert.IsFalse(ActionAt(Text, 3, Action));
  Assert.IsFalse(ActionAt(Text, 4, Action));
  Assert.IsFalse(ActionAt(Text, 5, Action));
end;

procedure TClassCompletionTests.MatchesOverloadsByParameters;
const
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    procedure Mehr(A: Integer); overload;'#10 +
    '    procedure Mehr(A: string); overload;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Mehr(A: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
var
  Action: TCodeAction;
begin
  Assert.IsTrue(ActionAt(Text, 5, Action));
  Assert.AreEqual('Methodenrumpf für TFoo.Mehr erzeugen', Action.Title);
  Assert.Contains(Apply(Text, Action), 'procedure TFoo.Mehr(A: string);'#10'begin');
  // Auf der schon implementierten Überladung: nur die fehlende.
  Assert.IsTrue(ActionAt(Text, 4, Action));
  Assert.AreEqual('Fehlenden Methodenrumpf für TFoo erzeugen', Action.Title);
  Assert.IsFalse(Action.Edits[0].NewText.Contains('Integer'));
end;

procedure TClassCompletionTests.NothingOutsideTypes;
var
  Action: TCodeAction;
begin
  Assert.IsFalse(ActionAt(Leer, 0, Action));
  Assert.IsFalse(ActionAt(Leer, 8, Action));
end;

initialization
  TDUnitX.RegisterTestFixture(TClassCompletionTests);

end.
