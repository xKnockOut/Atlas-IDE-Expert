unit Atlas.Common.Pascal.UsesEdits.Tests;

// Tests für das Lesen und Ergänzen von uses-Listen (#180).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUsesClauseTests = class
  public
    [Test]
    procedure AppendsToSingleLineUses;
    [Test]
    procedure AppendsToMultiLineUsesOnOwnLine;
    [Test]
    procedure ChoosesImplementationSectionByOffset;
    [Test]
    procedure CreatesUsesWhenMissing;
    [Test]
    procedure AddsToProgramUses;
    [Test]
    procedure FailsWithoutSection;
    [Test]
    procedure OrganizeRemovesDuplicates;
    [Test]
    procedure OrganizeSortsMultilineList;
    [Test]
    procedure OrganizeDropsEmptiedClause;
    [Test]
    procedure OrganizeKeepsListsWithDirectives;
    [Test]
    procedure OrganizeWithoutChangeGivesNothing;
    [Test]
    procedure GroupedWritesCommentPerGroup;
    [Test]
    procedure GroupedLinesStyleWithoutComments;
    [Test]
    procedure GroupedTwiceGivesNothing;
    [Test]
    procedure GroupedReplacesOldLabelsKeepsOtherComments;
    [Test]
    procedure GroupedWrapsLongGroups;
    [Test]
    procedure GroupedSingleGroupWithoutComment;
    [Test]
    procedure AddMissingUnitSkipsUsedUnits;
    [Test]
    procedure AppendsBehindLastEntryOfMultiLineUses;
    [Test]
    procedure AppendsOnOwnLineWhenLastLineIsFull;
    [Test]
    procedure SortKeepsCommentSections;
    [Test]
    procedure GroupedKeepsCommentSections;
    [Test]
    procedure TrailingCommentMovesWithEntry;
    [Test]
    procedure DropKeepsLayoutAndComments;
    [Test]
    procedure CommentAfterCommaIsKept;
    [Test]
    procedure SectionsTwiceGiveNothing;
    [Test]
    procedure ListWithDirectiveStaysUntouched;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.UsesGroups,
  Atlas.Common.Pascal.UsesEdits;

const
  cUnitText =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses System.SysUtils, Werkzeug in ''Werkzeug.pas'';'#10 +
    'implementation'#10 +
    'uses'#10 +
    '  Classes,'#10 +
    '  Daten.Kunden;'#10 +
    'procedure Rechne;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

function Apply(const AText: string; const AEdit: TTextEdit): string;
var
  mLines: TArray<string>;
  mLine: string;
begin
  // Einfügungen (StartPos = EndPos) in die Zeile übernehmen; die Tests brauchen nur das.
  mLines := AText.Split([#10]);
  mLine := mLines[AEdit.Range.StartPos.Line];
  Insert(AEdit.NewText, mLine, AEdit.Range.StartPos.Character + 1);
  mLines[AEdit.Range.StartPos.Line] := mLine;
  Result := string.Join(#10, mLines);
end;

function OffsetOf(const AText, AMarker: string): Integer;
begin
  Result := Pos(AMarker, AText) - 1;
end;

{ TUsesClauseTests }

procedure TUsesClauseTests.AppendsToSingleLineUses;
var
  mEdit: TTextEdit;
begin
  Assert.IsTrue(TPascalUsesEdits.AddUnit(TPascalLexer.Tokenize(cUnitText), OffsetOf(cUnitText, 'interface'),
    'Vcl.Forms', #10, mEdit));
  Assert.AreEqual('uses System.SysUtils, Werkzeug in ''Werkzeug.pas'', Vcl.Forms;', Apply(cUnitText, mEdit).Split([#10])[2]);
end;

procedure TUsesClauseTests.AppendsToMultiLineUsesOnOwnLine;
var
  mEdit: TTextEdit;
begin
  Assert.IsTrue(TPascalUsesEdits.AddUnit(TPascalLexer.Tokenize(cUnitText), OffsetOf(cUnitText, 'begin'), 'Vcl.Forms',
    #10, mEdit));
  Assert.IsTrue(Pos('uses'#10'  Classes,'#10'  Daten.Kunden,'#10'  Vcl.Forms;'#10'procedure',
    Apply(cUnitText, mEdit)) > 0, Apply(cUnitText, mEdit));
end;

procedure TUsesClauseTests.ChoosesImplementationSectionByOffset;
var
  mEdit: TTextEdit;
begin
  Assert.IsTrue(TPascalUsesEdits.AddUnit(TPascalLexer.Tokenize(cUnitText), OffsetOf(cUnitText, 'Rechne'), 'X', #10, mEdit));
  Assert.AreEqual(6, mEdit.Range.StartPos.Line);
  Assert.IsTrue(TPascalUsesEdits.AddUnit(TPascalLexer.Tokenize(cUnitText), OffsetOf(cUnitText, 'uses System'), 'X', #10, mEdit));
  Assert.AreEqual(2, mEdit.Range.StartPos.Line);
end;

procedure TUsesClauseTests.CreatesUsesWhenMissing;
const
  cText = 'unit A;'#10'interface'#10'implementation'#10'end.';
var
  mEdit: TTextEdit;
begin
  Assert.IsTrue(TPascalUsesEdits.AddUnit(TPascalLexer.Tokenize(cText), OffsetOf(cText, 'end.'), 'B', #10, mEdit));
  Assert.AreEqual('unit A;'#10'interface'#10'implementation'#10#10'uses'#10'  B;'#10'end.', Apply(cText, mEdit));
end;

procedure TUsesClauseTests.AddsToProgramUses;
const
  cText = 'program App;'#10'uses A;'#10'begin'#10'end.';
var
  mEdit: TTextEdit;
begin
  Assert.IsTrue(TPascalUsesEdits.AddUnit(TPascalLexer.Tokenize(cText), OffsetOf(cText, 'end.'), 'B', #10, mEdit));
  Assert.AreEqual('program App;'#10'uses A, B;'#10'begin'#10'end.', Apply(cText, mEdit));
end;

procedure TUsesClauseTests.FailsWithoutSection;
var
  mEdit: TTextEdit;
begin
  Assert.IsFalse(TPascalUsesEdits.AddUnit(TPascalLexer.Tokenize(''), 0, 'B', #10, mEdit));
  Assert.IsFalse(TPascalUsesEdits.AddUnit(TPascalLexer.Tokenize('unit A;'#10'type'), 0, 'B', #10, mEdit));
end;

/// <summary>Offset ab 0 zu einer Position; Zeilenwechsel #10.</summary>
function TextOffset(const AText: string; const APosition: TTextPosition): Integer;
var
  mLine: Integer;
begin
  Result := 0;
  mLine := 0;
  while mLine < APosition.Line do
  begin
    Inc(Result);
    if AText[Result] = #10 then
    begin
      Inc(mLine);
    end;
  end;
  Result := Result + APosition.Character;
end;

/// <summary>Edits (auch Ersetzungen) von hinten nach vorn anwenden, damit die Positionen gültig bleiben.</summary>
function ApplyAll(const AText: string; const AEdits: TArray<TTextEdit>): string;
var
  mIndex, mStartOffset, mEndOffset: Integer;
begin
  Result := AText;
  for mIndex := High(AEdits) downto 0 do
  begin
    mStartOffset := TextOffset(Result, AEdits[mIndex].Range.StartPos);
    mEndOffset := TextOffset(Result, AEdits[mIndex].Range.EndPos);
    Result := Copy(Result, 1, mStartOffset) + AEdits[mIndex].NewText + Copy(Result, mEndOffset + 1, MaxInt);
  end;
end;

function Organized(const AText: string; ASort: Boolean): string;
var
  mEdits: TArray<TTextEdit>;
begin
  if TPascalUsesEdits.Organize(TPascalLexer.Tokenize(AText), AText, ASort, #10, mEdits) then
  begin
    Result := ApplyAll(AText, mEdits);
  end
  else
  begin
    Result := AText;
  end;
end;

function NameGroups: TUsesGroupFunc;
begin
  Result :=
    function(const AUnitName: string): TUsesGroup
    begin
      Result := TUsesGroups.OfName(AUnitName);
    end;
end;

/// <summary>uses nach Herkunft gegliedert (#2794), Gruppen nur nach Namespace.</summary>
function Grouped(const AText: string; AStyle: TUsesGroupStyle; AMaxLength: Integer): string;
var
  mOptions: TUsesRewrite;
  mEdits: TArray<TTextEdit>;
begin
  mOptions := Default(TUsesRewrite);
  mOptions.Dedupe := True;
  mOptions.Sort := True;
  mOptions.GroupOf := NameGroups();
  mOptions.GroupStyle := AStyle;
  mOptions.MaxLineLength := AMaxLength;
  Result := AText;
  if TPascalUsesEdits.Rewrite(TPascalLexer.Tokenize(AText), AText, mOptions, #10, mEdits) then
  begin
    Result := ApplyAll(AText, mEdits);
  end;
end;

/// <summary>Kommentarzeile der Gruppe mit Einrückung und Zeilenwechsel.</summary>
function LabelLine(AGroup: TUsesGroup): string;
begin
  Result := '  ' + TUsesGroups.LabelOf(AGroup) + #10;
end;

const
  cMixedUses = 'unit A;'#10'interface'#10'uses Kunden.Daten, Vcl.Forms, System.SysUtils, IdHTTP, Vcl.Forms, ' +
    'System.Classes;'#10'implementation'#10'end.';

procedure TUsesClauseTests.GroupedWritesCommentPerGroup;
begin
  Assert.AreEqual('unit A;'#10'interface'#10'uses'#10 + LabelLine(TUsesGroup.RuntimeLibrary) +
    '  System.Classes, System.SysUtils,'#10 + LabelLine(TUsesGroup.DelphiComponents) + '  IdHTTP,'#10 +
    LabelLine(TUsesGroup.Framework) + '  Vcl.Forms,'#10 + LabelLine(TUsesGroup.Project) + '  Kunden.Daten;'#10 +
    'implementation'#10'end.', Grouped(cMixedUses, TUsesGroupStyle.Comments, 0));
end;

procedure TUsesClauseTests.GroupedLinesStyleWithoutComments;
begin
  Assert.AreEqual('unit A;'#10'interface'#10'uses'#10'  System.Classes, System.SysUtils,'#10'  IdHTTP,'#10 +
    '  Vcl.Forms,'#10'  Kunden.Daten;'#10'implementation'#10'end.', Grouped(cMixedUses, TUsesGroupStyle.Lines, 0));
end;

procedure TUsesClauseTests.GroupedTwiceGivesNothing;
var
  mText: string;
  mOptions: TUsesRewrite;
  mEdits: TArray<TTextEdit>;
begin
  mText := Grouped(cMixedUses, TUsesGroupStyle.Comments, 0);
  mOptions := Default(TUsesRewrite);
  mOptions.Dedupe := True;
  mOptions.Sort := True;
  mOptions.GroupOf := NameGroups();
  Assert.IsFalse(TPascalUsesEdits.Rewrite(TPascalLexer.Tokenize(mText), mText, mOptions, #10, mEdits));
end;

procedure TUsesClauseTests.GroupedReplacesOldLabelsKeepsOtherComments;
begin
  // Alte Gruppenkommentare (auch englisch) entfallen, ein eigener Kommentar vor dem ersten Eintrag bleibt.
  Assert.AreEqual('unit A;'#10'interface'#10'uses'#10'  { Formulare }'#10 + LabelLine(TUsesGroup.RuntimeLibrary) +
    '  System.SysUtils,'#10 + LabelLine(TUsesGroup.Framework) + '  Vcl.Forms;'#10'implementation'#10'end.',
    Grouped('unit A;'#10'interface'#10'uses'#10'  { Formulare }'#10'  { Library }'#10'  Vcl.Forms,'#10 +
    '  { Project }'#10'  System.SysUtils;'#10'implementation'#10'end.', TUsesGroupStyle.Comments, 0));
end;

procedure TUsesClauseTests.GroupedWrapsLongGroups;
begin
  Assert.AreEqual('unit A;'#10'interface'#10'uses'#10'  System.Classes, System.SysUtils,'#10'  Winapi.Windows;'#10 +
    'implementation'#10'end.', Grouped('unit A;'#10'interface'#10'uses Winapi.Windows, System.SysUtils, ' +
    'System.Classes;'#10'implementation'#10'end.', TUsesGroupStyle.Comments, 40));
end;

procedure TUsesClauseTests.GroupedSingleGroupWithoutComment;
begin
  Assert.AreEqual('program P;'#10'uses'#10'  Alpha, Main in ''Main.pas'' {Form1};'#10'begin end.',
    Grouped('program P;'#10'uses'#10'  Main in ''Main.pas'' {Form1},'#10'  Alpha;'#10'begin end.',
    TUsesGroupStyle.Comments, 0));
end;

procedure TUsesClauseTests.OrganizeRemovesDuplicates;
begin
  Assert.AreEqual('unit A;'#10'interface'#10'uses B, C;'#10'implementation'#10'uses D;'#10'end.',
    Organized('unit A;'#10'interface'#10'uses B, C, b;'#10'implementation'#10'uses C, D;'#10'end.', False));
end;

procedure TUsesClauseTests.OrganizeSortsMultilineList;
begin
  Assert.AreEqual('program P;'#10'uses'#10'  Alpha,'#10'  Main in ''Main.pas'' {Form1},'#10'  Zeta;'#10'begin end.',
    Organized('program P;'#10'uses'#10'  Zeta,'#10'  Main in ''Main.pas'' {Form1},'#10'  Alpha;'#10'begin end.', True));
end;

procedure TUsesClauseTests.OrganizeDropsEmptiedClause;
begin
  Assert.AreEqual('unit A;'#10'interface'#10'uses B;'#10'implementation'#10#10'end.',
    Organized('unit A;'#10'interface'#10'uses B;'#10'implementation'#10'uses B;'#10'end.', False));
end;

procedure TUsesClauseTests.OrganizeKeepsListsWithDirectives;
const
  cText = 'unit A;'#10'interface'#10'uses Z, {$IFDEF X} Y, {$ENDIF} A;'#10'implementation'#10'end.';
begin
  Assert.AreEqual(cText, Organized(cText, True));
end;

procedure TUsesClauseTests.OrganizeWithoutChangeGivesNothing;
var
  mEdits: TArray<TTextEdit>;
const
  cText = 'unit A;'#10'interface'#10'uses A1, B2;'#10'implementation'#10'end.';
begin
  Assert.IsFalse(TPascalUsesEdits.Organize(TPascalLexer.Tokenize(cText), cText, True, #10, mEdits));
end;

procedure TUsesClauseTests.AddMissingUnitSkipsUsedUnits;
var
  mEdit: TTextEdit;
begin
  Assert.IsFalse(TPascalUsesEdits.AddMissingUnit(TPascalLexer.Tokenize(cUnitText), OffsetOf(cUnitText, 'interface'),
    'System.SysUtils', TArray<string>.Create('System'), #10, mEdit), 'schon eingebunden');
  Assert.IsFalse(TPascalUsesEdits.AddMissingUnit(TPascalLexer.Tokenize(cUnitText), OffsetOf(cUnitText, 'interface'),
    'Daten.Werkzeug', nil, #10, mEdit), 'ohne Namespace schon eingebunden');
  Assert.IsTrue(TPascalUsesEdits.AddMissingUnit(TPascalLexer.Tokenize(cUnitText), OffsetOf(cUnitText, 'interface'),
    'Vcl.Forms', nil, #10, mEdit));
  Assert.AreEqual('uses System.SysUtils, Werkzeug in ''Werkzeug.pas'', Vcl.Forms;',
    Apply(cUnitText, mEdit).Split([#10])[2]);
end;

procedure TUsesClauseTests.AppendsBehindLastEntryOfMultiLineUses;
const
  cText = 'unit A;'#10'interface'#10'uses'#10'  Classes, SysUtils;'#10'implementation'#10'end.';
var
  mEdit: TTextEdit;
begin
  // Mehrere Einträge je Zeile: Die neue Unit kommt dahinter, nicht in eine eigene Zeile.
  Assert.IsTrue(TPascalUsesEdits.AddUnit(TPascalLexer.Tokenize(cText), OffsetOf(cText, 'interface'), 'Vcl.Forms', #10,
    mEdit));
  Assert.AreEqual('unit A;'#10'interface'#10'uses'#10'  Classes, SysUtils, Vcl.Forms;'#10'implementation'#10'end.',
    Apply(cText, mEdit));
end;

procedure TUsesClauseTests.AppendsOnOwnLineWhenLastLineIsFull;
var
  mText: string;
  mEdit: TTextEdit;
begin
  mText := 'unit A;'#10'interface'#10'uses'#10'  ' + StringOfChar('X', 110) + ', Y;'#10'implementation'#10'end.';
  Assert.IsTrue(TPascalUsesEdits.AddUnit(TPascalLexer.Tokenize(mText), OffsetOf(mText, 'interface'), 'Vcl.Forms', #10,
    mEdit));
  Assert.IsTrue(Pos(', Y,'#10'  Vcl.Forms;', Apply(mText, mEdit)) > 0, Apply(mText, mEdit));
end;

const
  cSectionUses = 'unit A;'#10'interface'#10'uses'#10'  Dialogs, RTTI,'#10'  // Formulare - ABC'#10 +
    '  uFormC, uFormA, uFormB,'#10'  // Formulare - DEF'#10'  uFormF, uFormD, System.SysUtils;'#10'implementation'#10 +
    'end.';

procedure TUsesClauseTests.SortKeepsCommentSections;
begin
  // Kommentarzeilen bleiben Überschriften, sortiert wird je Abschnitt (#2794 mit Kommentaren).
  Assert.AreEqual('unit A;'#10'interface'#10'uses'#10'  Dialogs, RTTI,'#10'  // Formulare - ABC'#10 +
    '  uFormA, uFormB, uFormC,'#10'  // Formulare - DEF'#10'  System.SysUtils, uFormD, uFormF;'#10'implementation'#10 +
    'end.', Organized(cSectionUses, True));
end;

procedure TUsesClauseTests.GroupedKeepsCommentSections;
begin
  // Nach Herkunft: je Abschnitt nach Gruppe, neue Zeile bei neuer Gruppe, keine Gruppenkommentare.
  Assert.AreEqual('unit A;'#10'interface'#10'uses'#10'  Dialogs, RTTI,'#10'  // Formulare - ABC'#10 +
    '  uFormA, uFormB, uFormC,'#10'  // Formulare - DEF'#10'  System.SysUtils,'#10'  uFormD, uFormF;'#10 +
    'implementation'#10'end.', Grouped(cSectionUses, TUsesGroupStyle.Comments, 0));
end;

procedure TUsesClauseTests.TrailingCommentMovesWithEntry;
begin
  Assert.AreEqual('unit A;'#10'interface'#10'uses'#10'  Alpha, Beta, // für Rechne'#10'  Gamma;'#10 +
    'implementation'#10'end.', Organized('unit A;'#10'interface'#10'uses'#10'  Gamma,'#10 +
    '  Beta, // für Rechne'#10'  Alpha;'#10'implementation'#10'end.', True));
  // Landet ein Eintrag mit //-Kommentar am Ende, steht das Semikolon vor dem Kommentar.
  Assert.AreEqual('unit A;'#10'interface'#10'uses'#10'  Alpha, Beta; // für Rechne'#10 +
    'implementation'#10'end.', Organized('unit A;'#10'interface'#10'uses'#10'  Beta, // für Rechne'#10 +
    '  Alpha;'#10'implementation'#10'end.', True));
end;

procedure TUsesClauseTests.DropKeepsLayoutAndComments;
var
  mOptions: TUsesRewrite;
  mEdits: TArray<TTextEdit>;
  mText: string;
begin
  // Ohne Sortieren (/cleanuses): Zeilen und Kommentare bleiben, nur der gestrichene Eintrag fällt weg.
  mText := 'unit A;'#10'interface'#10'uses'#10'  Gamma, Beta,'#10'  // Formulare'#10'  uFormB, uFormA;'#10 +
    'implementation'#10'end.';
  mOptions := Default(TUsesRewrite);
  mOptions.Drop := ['Beta'];
  Assert.IsTrue(TPascalUsesEdits.Rewrite(TPascalLexer.Tokenize(mText), mText, mOptions, #10, mEdits));
  Assert.AreEqual('unit A;'#10'interface'#10'uses'#10'  Gamma,'#10'  // Formulare'#10'  uFormB, uFormA;'#10 +
    'implementation'#10'end.', ApplyAll(mText, mEdits));
end;

procedure TUsesClauseTests.CommentAfterCommaIsKept;
begin
  Assert.AreEqual('unit A;'#10'interface'#10'uses'#10'  Alpha, { alt } Beta;'#10'implementation'#10'end.',
    Organized('unit A;'#10'interface'#10'uses'#10'  Beta, Alpha, { alt }'#10'  Beta;'#10'implementation'#10'end.',
    True));
end;

procedure TUsesClauseTests.SectionsTwiceGiveNothing;
var
  mText: string;
  mOptions: TUsesRewrite;
  mEdits: TArray<TTextEdit>;
begin
  mText := Grouped(cSectionUses, TUsesGroupStyle.Comments, 0);
  mOptions := Default(TUsesRewrite);
  mOptions.Dedupe := True;
  mOptions.Sort := True;
  mOptions.GroupOf := NameGroups();
  Assert.IsFalse(TPascalUsesEdits.Rewrite(TPascalLexer.Tokenize(mText), mText, mOptions, #10, mEdits));
end;

procedure TUsesClauseTests.ListWithDirectiveStaysUntouched;
const
  cText = 'unit A;'#10'interface'#10'uses'#10'  Beta, // b'#10'  {$IFDEF X} Alpha, {$ENDIF}'#10'  Gamma;'#10 +
    'implementation'#10'end.';
begin
  Assert.AreEqual(cText, Organized(cText, True));
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesClauseTests);

end.
