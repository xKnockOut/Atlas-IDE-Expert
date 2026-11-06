unit Atlas.Common.Editing.ClassCompletion.Tests;

interface

// Fehlende Methodenrümpfe (#647). Typkommentar in vier Formen (#1835),
// Lebenszyklus und Get/Set-Paare zuerst (#1836), vorbefüllte Rümpfe (#1837).

uses
  DUnitX.TestFramework,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassBodies;

type
  [TestFixture]
  TClassCompletionTests = class
  private
    function ActionAt(const AText: string; ALine: Integer; out AAction: TCodeAction): Boolean;
    function ActionWith(const AText: string; ALine: Integer; const AOptions: TClassBodyOptions;
      out AAction: TCodeAction): Boolean;
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
    [Test]
    procedure IgnoresDefaultsAndGrouping;
    [Test]
    procedure TypeCommentStyles;
    [Test]
    procedure NoSecondTypeComment;
    [Test]
    procedure OrdersLifecycleAndAccessorsFirst;
    [Test]
    procedure PrefillsBodies;
    [Test]
    procedure EmptyBodiesWhenStubsOff;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.TypeComments,
  Atlas.Common.Editing.ClassCompletion;

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

procedure TClassCompletionTests.IgnoresDefaultsAndGrouping;
const
  // Die Implementierung lässt Standardwerte weg und gruppiert anders (#647).
  Text =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    procedure Lauf(const A: string; const B: string = ''''; C: Integer = 0);'#10 +
    '    procedure Wert(X, Y: TArray<Integer>; Z: Integer = Ord('';''));'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Lauf(const A, B: string; C: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TFoo.Wert(X: TArray<Integer>; Y: TArray<Integer>; Z: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
  Anders =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    procedure Lauf(const A: string; B: Integer = 0);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Lauf(const A: string; B: string);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Text);
  try
    Assert.AreEqual(0, Integer(Length(TClassCompletion.Unmatched(Tree, Text))));
  finally
    Tree.Free;
  end;
  // Verschiedene Typen passen weiterhin nicht.
  Tree := TPascalParser.Parse(Anders);
  try
    Assert.AreEqual(2, Integer(Length(TClassCompletion.Unmatched(Tree, Anders))));
  finally
    Tree.Free;
  end;
end;

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

function TClassCompletionTests.ActionWith(const AText: string; ALine: Integer; const AOptions: TClassBodyOptions;
  out AAction: TCodeAction): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TClassCompletion.MissingBodies(Tree, AText, TTextPosition.Create(ALine, 6), AOptions, AAction);
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
  Assert.AreEqual(cRewriteKind, Action.Kind);
  Assert.AreEqual(
    'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'    procedure Lauf(A: Integer);'#10 +
    '    function Wert: string; virtual;'#10'  end;'#10'implementation'#10#10'{ TFoo }'#10#10 +
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
  // Kennung für „Anweisung vervollständigen“ im Plugin (#697).
  Assert.AreEqual(cClassBodiesTag, Action.Tag);
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

const
  Fenster =
    'unit U;'#10 +                                              // 0
    'interface'#10 +                                            // 1
    'type'#10 +                                                 // 2
    '  /// <summary>Hauptfenster der Anwendung.</summary>'#10 + // 3
    '  TFenster = class(TBasis)'#10 +                           // 4
    '  private'#10 +
    '    FName: string;'#10 +
    '    FAlter: Integer;'#10 +
    '    procedure Zeichnen;'#10 +
    '    function GetName: string;'#10 +
    '    procedure SetName(const AValue: string);'#10 +
    '    function GetAlter: Integer;'#10 +
    '  protected'#10 +
    '    function Wert(A, B: Integer): Integer; override;'#10 +
    '    procedure Paint; override;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    destructor Destroy; override;'#10 +
    '    property Name: string read GetName write SetName;'#10 +
    '    property Alter: Integer read GetAlter;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    #10 +
    'end.';

function OptionsWith(AStyle: TTypeCommentStyle): TClassBodyOptions;
begin
  Result := TClassBodyOptions.Default;
  Result.TypeComment := AStyle;
end;

/// <summary>Stelle von APart in AText; schlägt fehl, wenn es fehlt.</summary>
function At(const AText, APart: string): Integer;
begin
  Result := Pos(APart, AText);
  Assert.IsTrue(Result > 0, 'fehlt: ' + APart);
end;

procedure TClassCompletionTests.TypeCommentStyles;
var
  Action: TCodeAction;
  Text: string;
begin
  Assert.IsTrue(ActionWith(Leer, 3, OptionsWith(TTypeCommentStyle.Off), Action));
  Assert.AreEqual(0, Pos('{ TFoo }', Apply(Leer, Action)), 'aus: kein Kommentar');
  Assert.IsTrue(ActionWith(Leer, 3, OptionsWith(TTypeCommentStyle.Line), Action));
  Text := Apply(Leer, Action);
  Assert.IsTrue(At(Text, '//---') < At(Text, '// TFoo'#10'//---'), 'Trennlinie darüber und darunter');
  Assert.IsTrue(ActionWith(Fenster, 4, OptionsWith(TTypeCommentStyle.Summary), Action));
  At(Apply(Fenster, Action), '{ TFenster: Hauptfenster der Anwendung. }');
  Assert.IsTrue(ActionWith(Leer, 3, OptionsWith(TTypeCommentStyle.Region), Action));
  Text := Apply(Leer, Action);
  Assert.IsTrue(At(Text, '{$REGION ''TFoo''}') < At(Text, 'procedure TFoo.Lauf'));
  Assert.IsTrue(At(Text, 'function TFoo.Wert') < At(Text, '{$ENDREGION}'), 'Region um alle Rümpfe');
end;

procedure TClassCompletionTests.NoSecondTypeComment;
const
  Halb =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    procedure Lauf(A: Integer);'#10 +
    '    function Wert: string; virtual;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    #10 +
    '{ TFoo }'#10 +
    #10 +
    'procedure TFoo.Lauf(A: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    #10 +
    'end.';
var
  Action: TCodeAction;
  Text: string;
begin
  Assert.IsTrue(ActionWith(Halb, 5, TClassBodyOptions.Default, Action));
  Text := Apply(Halb, Action);
  At(Text, 'function TFoo.Wert: string;');
  Assert.AreEqual(0, Pos('{ TFoo }', Copy(Text, At(Text, '{ TFoo }') + 1, MaxInt)), 'kein zweiter Kommentar');
end;

procedure TClassCompletionTests.OrdersLifecycleAndAccessorsFirst;
var
  Action: TCodeAction;
  Text: string;
begin
  Assert.IsTrue(ActionWith(Fenster, 4, TClassBodyOptions.Default, Action));
  Text := Apply(Fenster, Action);
  Assert.IsTrue(At(Text, 'constructor TFenster.Create') < At(Text, 'destructor TFenster.Destroy'));
  Assert.IsTrue(At(Text, 'destructor TFenster.Destroy') < At(Text, 'function TFenster.GetName'));
  Assert.IsTrue(At(Text, 'function TFenster.GetName') < At(Text, 'procedure TFenster.SetName'), 'Get/Set-Paar');
  Assert.IsTrue(At(Text, 'procedure TFenster.SetName') < At(Text, 'function TFenster.GetAlter'),
    'Eigenschaften in ihrer Reihenfolge');
  Assert.IsTrue(At(Text, 'function TFenster.GetAlter') < At(Text, 'function TFenster.Wert'));
  Assert.IsTrue(At(Text, 'function TFenster.Wert') < At(Text, 'procedure TFenster.Paint'), 'Überschreibungen');
  Assert.IsTrue(At(Text, 'procedure TFenster.Paint') < At(Text, 'procedure TFenster.Zeichnen'), 'Rest zuletzt');
end;

procedure TClassCompletionTests.PrefillsBodies;
var
  Action: TCodeAction;
  Text: string;
begin
  Assert.IsTrue(ActionWith(Fenster, 4, TClassBodyOptions.Default, Action));
  Text := Apply(Fenster, Action);
  At(Text, 'constructor TFenster.Create;'#10'begin'#10'  inherited Create;'#10'end;');
  At(Text, 'destructor TFenster.Destroy;'#10'begin'#10#10'  inherited;'#10'end;');
  At(Text, 'function TFenster.GetName: string;'#10'begin'#10'  Result := FName;'#10'end;');
  At(Text, 'procedure TFenster.SetName(const AValue: string);'#10'begin'#10'  FName := AValue;'#10'end;');
  At(Text, 'function TFenster.GetAlter: Integer;'#10'begin'#10'  Result := FAlter;'#10'end;');
  At(Text, 'function TFenster.Wert(A, B: Integer): Integer;'#10'begin'#10'  Result := inherited Wert(A, B);'#10 +
    'end;');
  At(Text, 'procedure TFenster.Paint;'#10'begin'#10'  inherited Paint;'#10'end;');
  At(Text, 'procedure TFenster.Zeichnen;'#10'begin'#10#10'end;');
end;

procedure TClassCompletionTests.EmptyBodiesWhenStubsOff;
var
  Options: TClassBodyOptions;
  Action: TCodeAction;
  Text: string;
begin
  Options := TClassBodyOptions.Default;
  Options.BodyStubs := False;
  Assert.IsTrue(ActionWith(Fenster, 4, Options, Action));
  Text := Apply(Fenster, Action);
  Assert.AreEqual(0, Pos('inherited', Text));
  Assert.AreEqual(0, Pos('Result :=', Text));
end;

initialization
  TDUnitX.RegisterTestFixture(TClassCompletionTests);

end.
