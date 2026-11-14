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
  cLeer =
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
  cText =
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
  cAnders =
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
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cText);
  try
    Assert.AreEqual(0, Integer(Length(TClassCompletion.Unmatched(mTree, cText))));
  finally
    mTree.Free;
  end;
  // Verschiedene Typen passen weiterhin nicht.
  mTree := TPascalParser.Parse(cAnders);
  try
    Assert.AreEqual(2, Integer(Length(TClassCompletion.Unmatched(mTree, cAnders))));
  finally
    mTree.Free;
  end;
end;

function TClassCompletionTests.ActionAt(const AText: string; ALine: Integer; out AAction: TCodeAction): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := TClassCompletion.MissingBodies(mTree, AText, TTextPosition.Create(ALine, 6), AAction);
  finally
    mTree.Free;
  end;
end;

function TClassCompletionTests.ActionWith(const AText: string; ALine: Integer; const AOptions: TClassBodyOptions;
  out AAction: TCodeAction): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := TClassCompletion.MissingBodies(mTree, AText, TTextPosition.Create(ALine, 6), AOptions, AAction);
  finally
    mTree.Free;
  end;
end;

function TClassCompletionTests.Apply(const AText: string; const AAction: TCodeAction): string;
var
  mLines: TArray<string>;
  mEdit: TRuleEdit;
  mLine: string;
begin
  // Genau eine Einfügung.
  Assert.AreEqual(1, Integer(Length(AAction.Edits)));
  mEdit := AAction.Edits[0];
  mLines := AText.Split([#10]);
  mLine := mLines[mEdit.Range.StartPos.Line];
  mLines[mEdit.Range.StartPos.Line] := Copy(mLine, 1, mEdit.Range.StartPos.Character) + mEdit.NewText +
    Copy(mLine, mEdit.Range.EndPos.Character + 1, MaxInt);
  Result := string.Join(#10, mLines);
end;

procedure TClassCompletionTests.AddsSingleMissingBody;
var
  mAction: TCodeAction;
begin
  Assert.IsTrue(ActionAt(cLeer, 4, mAction));
  Assert.AreEqual('Methodenrumpf für TFoo.Lauf erzeugen', mAction.Title);
  Assert.AreEqual(cRewriteKind, mAction.Kind);
  Assert.AreEqual(
    'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'    procedure Lauf(A: Integer);'#10 +
    '    function Wert: string; virtual;'#10'  end;'#10'implementation'#10#10'{ TFoo }'#10#10 +
    'procedure TFoo.Lauf(A: Integer);'#10'begin'#10#10'end;'#10#10'end.',
    Apply(cLeer, mAction));
end;

procedure TClassCompletionTests.AddsAllMissingBodiesOfType;
var
  mAction: TCodeAction;
  mText: string;
begin
  // Cursor auf der Typzeile: alle fehlenden Rümpfe.
  Assert.IsTrue(ActionAt(cLeer, 3, mAction));
  Assert.AreEqual('2 fehlende Methodenrümpfe für TFoo erzeugen', mAction.Title);
  // Kennung für „Anweisung vervollständigen“ im Plugin (#697).
  Assert.AreEqual(cClassBodiesTag, mAction.Tag);
  mText := Apply(cLeer, mAction);
  Assert.Contains(mText, 'procedure TFoo.Lauf(A: Integer);'#10'begin'#10#10'end;'#10#10 +
    'function TFoo.Wert: string;'#10'begin'#10#10'end;'#10#10'end.');
end;

procedure TClassCompletionTests.InsertsAfterLastMethodOfType;
const
  cText =
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
  mAction: TCodeAction;
begin
  Assert.IsTrue(ActionAt(cText, 5, mAction));
  Assert.Contains(Apply(cText, mAction),
    'procedure TFoo.Eins;'#10'begin'#10'end;'#10#10'procedure TFoo.Zwei;'#10'begin'#10#10'end;'#10'procedure Frei;');
end;

procedure TClassCompletionTests.KeepsFunctionsAndClassMethods;
const
  cText =
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
  mAction: TCodeAction;
  mApplied: string;
begin
  Assert.IsTrue(ActionAt(cText, 3, mAction));
  mApplied := Apply(cText, mAction);
  Assert.Contains(mApplied, 'class function TFoo.Neu(const A: string; B: Integer): TFoo;'#10'begin');
  Assert.Contains(mApplied, 'constructor TFoo.Create;'#10'begin');
  // Direktiven wie static gehören nicht in die Implementierung.
  Assert.IsFalse(mAction.Edits[0].NewText.Contains('static'));
end;

procedure TClassCompletionTests.SkipsImplementedAndAbstractMethods;
const
  cText =
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
  mAction: TCodeAction;
begin
  Assert.IsFalse(ActionAt(cText, 3, mAction));
  Assert.IsFalse(ActionAt(cText, 4, mAction));
  Assert.IsFalse(ActionAt(cText, 5, mAction));
end;

procedure TClassCompletionTests.MatchesOverloadsByParameters;
const
  cText =
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
  mAction: TCodeAction;
begin
  Assert.IsTrue(ActionAt(cText, 5, mAction));
  Assert.AreEqual('Methodenrumpf für TFoo.Mehr erzeugen', mAction.Title);
  Assert.Contains(Apply(cText, mAction), 'procedure TFoo.Mehr(A: string);'#10'begin');
  // Auf der schon implementierten Überladung: nur die fehlende.
  Assert.IsTrue(ActionAt(cText, 4, mAction));
  Assert.AreEqual('Fehlenden Methodenrumpf für TFoo erzeugen', mAction.Title);
  Assert.IsFalse(mAction.Edits[0].NewText.Contains('Integer'));
end;

procedure TClassCompletionTests.NothingOutsideTypes;
var
  mAction: TCodeAction;
begin
  Assert.IsFalse(ActionAt(cLeer, 0, mAction));
  Assert.IsFalse(ActionAt(cLeer, 8, mAction));
end;

const
  cFenster =
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
  mAction: TCodeAction;
  mText: string;
begin
  Assert.IsTrue(ActionWith(cLeer, 3, OptionsWith(TTypeCommentStyle.Off), mAction));
  Assert.AreEqual(0, Pos('{ TFoo }', Apply(cLeer, mAction)), 'aus: kein Kommentar');
  Assert.IsTrue(ActionWith(cLeer, 3, OptionsWith(TTypeCommentStyle.Line), mAction));
  mText := Apply(cLeer, mAction);
  Assert.IsTrue(At(mText, '//---') < At(mText, '// TFoo'#10'//---'), 'Trennlinie darüber und darunter');
  Assert.IsTrue(ActionWith(cFenster, 4, OptionsWith(TTypeCommentStyle.Summary), mAction));
  At(Apply(cFenster, mAction), '{ TFenster: Hauptfenster der Anwendung. }');
  Assert.IsTrue(ActionWith(cLeer, 3, OptionsWith(TTypeCommentStyle.Region), mAction));
  mText := Apply(cLeer, mAction);
  Assert.IsTrue(At(mText, '{$REGION ''TFoo''}') < At(mText, 'procedure TFoo.Lauf'));
  Assert.IsTrue(At(mText, 'function TFoo.Wert') < At(mText, '{$ENDREGION}'), 'Region um alle Rümpfe');
end;

procedure TClassCompletionTests.NoSecondTypeComment;
const
  cHalb =
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
  mAction: TCodeAction;
  mText: string;
begin
  Assert.IsTrue(ActionWith(cHalb, 5, TClassBodyOptions.Default, mAction));
  mText := Apply(cHalb, mAction);
  At(mText, 'function TFoo.Wert: string;');
  Assert.AreEqual(0, Pos('{ TFoo }', Copy(mText, At(mText, '{ TFoo }') + 1, MaxInt)), 'kein zweiter Kommentar');
end;

procedure TClassCompletionTests.OrdersLifecycleAndAccessorsFirst;
var
  mAction: TCodeAction;
  mText: string;
begin
  Assert.IsTrue(ActionWith(cFenster, 4, TClassBodyOptions.Default, mAction));
  mText := Apply(cFenster, mAction);
  Assert.IsTrue(At(mText, 'constructor TFenster.Create') < At(mText, 'destructor TFenster.Destroy'));
  Assert.IsTrue(At(mText, 'destructor TFenster.Destroy') < At(mText, 'function TFenster.GetName'));
  Assert.IsTrue(At(mText, 'function TFenster.GetName') < At(mText, 'procedure TFenster.SetName'), 'Get/Set-Paar');
  Assert.IsTrue(At(mText, 'procedure TFenster.SetName') < At(mText, 'function TFenster.GetAlter'),
    'Eigenschaften in ihrer Reihenfolge');
  Assert.IsTrue(At(mText, 'function TFenster.GetAlter') < At(mText, 'function TFenster.Wert'));
  Assert.IsTrue(At(mText, 'function TFenster.Wert') < At(mText, 'procedure TFenster.Paint'), 'Überschreibungen');
  Assert.IsTrue(At(mText, 'procedure TFenster.Paint') < At(mText, 'procedure TFenster.Zeichnen'), 'Rest zuletzt');
end;

procedure TClassCompletionTests.PrefillsBodies;
var
  mAction: TCodeAction;
  mText: string;
begin
  Assert.IsTrue(ActionWith(cFenster, 4, TClassBodyOptions.Default, mAction));
  mText := Apply(cFenster, mAction);
  At(mText, 'constructor TFenster.Create;'#10'begin'#10'  inherited Create;'#10'end;');
  At(mText, 'destructor TFenster.Destroy;'#10'begin'#10#10'  inherited;'#10'end;');
  At(mText, 'function TFenster.GetName: string;'#10'begin'#10'  Result := FName;'#10'end;');
  At(mText, 'procedure TFenster.SetName(const AValue: string);'#10'begin'#10'  FName := AValue;'#10'end;');
  At(mText, 'function TFenster.GetAlter: Integer;'#10'begin'#10'  Result := FAlter;'#10'end;');
  At(mText, 'function TFenster.Wert(A, B: Integer): Integer;'#10'begin'#10'  Result := inherited Wert(A, B);'#10 +
    'end;');
  At(mText, 'procedure TFenster.Paint;'#10'begin'#10'  inherited Paint;'#10'end;');
  At(mText, 'procedure TFenster.Zeichnen;'#10'begin'#10#10'end;');
end;

procedure TClassCompletionTests.EmptyBodiesWhenStubsOff;
var
  mOptions: TClassBodyOptions;
  mAction: TCodeAction;
  mText: string;
begin
  mOptions := TClassBodyOptions.Default;
  mOptions.BodyStubs := False;
  Assert.IsTrue(ActionWith(cFenster, 4, mOptions, mAction));
  mText := Apply(cFenster, mAction);
  Assert.AreEqual(0, Pos('inherited', mText));
  Assert.AreEqual(0, Pos('Result :=', mText));
end;

initialization
  TDUnitX.RegisterTestFixture(TClassCompletionTests);

end.
