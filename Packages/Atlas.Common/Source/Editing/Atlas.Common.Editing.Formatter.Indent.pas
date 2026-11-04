unit Atlas.Common.Editing.Formatter.Indent;

// Einrückung aus der Blockstruktur (#43). Ein Durchlauf über die Tokens hält
// einen Stapel offener Blöcke (begin, try, case, Klassenrumpf, Abschnitte wie
// var, Routinen, if/else/do mit einer einzelnen Anweisung) und bestimmt für
// jede Zeile, die eine Anweisung oder Deklaration beginnt, die Spalte. Zeilen,
// die eine Anweisung fortsetzen, behalten ihren Abstand zur ersten Zeile der
// Anweisung; Kommentarzeilen den zur folgenden Codezeile. Unverändert bleiben
// Zeilen mit einer Direktive am Anfang, asm-Blöcke, Zeilen in mehrzeiligen
// Tokens und die Zweige hinter {$ELSE} (der erste Zweig bestimmt den Aufbau).

interface

uses
  Atlas.Common.Pascal.Contract;

type
  TBlockIndenter = class
  public const
    /// <summary>Zeile bleibt, wie sie ist.</summary>
    Keep = -1;
  public
    /// <summary>Zielspalte je Zeile (Keep = unverändert). AColumns: vorhandene Einrückung je Zeile in Spalten;
    /// AIndentSize: Breite einer Ebene.</summary>
    class function Columns(const ATokens: TArray<TPascalToken>; const AColumns: TArray<Integer>;
      AIndentSize: Integer): TArray<Integer>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math;

type
  TFrameKind = (Top, Section, ClassBody, Routine, Block, TryBlock, RepeatBlock, CaseBlock, AsmBlock, InitBlock,
    IfPending, ElsePending, DoPending, LabelPending);
  TFrameKinds = set of TFrameKind;

  TFrame = record
    Kind: TFrameKind;
    Column: Integer;
    /// <summary>Klammertiefe beim Öffnen; ; und : zählen nur auf dieser Tiefe.</summary>
    Depth: Integer;
    /// <summary>Routine: Rumpf (begin/asm) hat begonnen.</summary>
    HasBody: Boolean;
    /// <summary>Routine: forward oder external, kein Rumpf.</summary>
    NoBody: Boolean;
    /// <summary>Routine: anonyme Methode im Ausdruck.</summary>
    Anonymous: Boolean;
    /// <summary>CaseBlock: Teil hinter else.</summary>
    InElse: Boolean;
    /// <summary>CaseBlock: eine Marke hat begonnen, ihr : steht noch aus.</summary>
    InLabel: Boolean;
    /// <summary>CaseBlock: varianter Teil eines Records, ohne eigenes end.</summary>
    Variant: Boolean;
    /// <summary>Anonyme Methode: Stand der umgebenden Anweisung, gilt nach ihrem end wieder.</summary>
    OuterStmtLine: Integer;
    OuterPendingCase: Boolean;
    OuterCaseColumn: Integer;
  end;

  /// <summary>Stand des Durchlaufs: Stapel offener Blöcke und die laufende Anweisung.</summary>
  TIndentState = record
    Frames: TArray<TFrame>;
    Count: Integer;
    AtStart: Boolean;
    Depth: Integer;
    StmtLine: Integer;
    /// <summary>Routinenkopf mit Rumpf; die Routine öffnet beim ; des Kopfes.</summary>
    PendingRoutine: Boolean;
    RoutineColumn: Integer;
    PendingCase: Boolean;
    CaseColumn: Integer;
    /// <summary>"class" vor procedure, function, operator usw.</summary>
    ClassPrefix: Boolean;
    /// <summary>Token, hinter dem der Kopf eines Klassenrumpfs endet; -1 ohne.</summary>
    HeaderEnd: Integer;
    /// <summary>Anweisung beginnt mit [ (Attribut, GUID).</summary>
    Attribute: Boolean;
    InImplementation: Boolean;
    HasBodies: Boolean;
    /// <summary>Die letzte Anweisung war ein Routinen- oder Property-Kopf; Direktiven wie static oder
    /// overload in der nächsten Zeile setzen ihn fort.</summary>
    AfterHeader: Boolean;
    procedure Push(AKind: TFrameKind; AColumn: Integer);
    procedure Pop;
    /// <summary>Schließt alles bis auf den untersten Rahmen (Datei).</summary>
    procedure PopAll;
    /// <summary>Schließt Rahmen, bis einer der Art AKinds oben liegt.</summary>
    procedure PopUntil(AKinds: TFrameKinds);
    procedure PopPending;
    procedure PopSections;
    function TopKind: TFrameKind;
    function TopFrame: TFrame;
    class function IsPending(AKind: TFrameKind): Boolean; static;
    /// <summary>Oberster Rahmen, der kein Abschnitt (var, const …) ist.</summary>
    function DeclIndex: Integer;
    function DeclKind: TFrameKind;
    function InStatements: Boolean;
    /// <summary>Kopie mit eigenem Stapel.</summary>
    function Copied: TIndentState;
  end;

  TBranch = record
    Saved: TIndentState;
    FirstEnd: TIndentState;
    Alternative: Boolean;
  end;

  /// <summary>Zweige der bedingten Übersetzung: Der erste Zweig bestimmt den Aufbau; hinter {$ELSE} gilt wieder der
  /// Stand vor {$IF}, nach {$ENDIF} der vom Ende des ersten Zweigs.</summary>
  TBranchTracker = record
    Branches: TArray<TBranch>;
    /// <summary>Anzahl offener Zweige hinter {$ELSE}; dort wird nichts gesetzt.</summary>
    Alternatives: Integer;
    procedure Directive(const AToken: TPascalToken; var AState: TIndentState);
  private
    procedure OtherBranch(var AState: TIndentState);
    procedure EndBranch(var AState: TIndentState);
  end;

  /// <summary>Lesen in den Tokens ohne Kommentare und Direktiven.</summary>
  TIndentTokens = record
    Tokens: TArray<TPascalToken>;
    function NextSignificant(AIndex: Integer): Integer;
    function PreviousSignificant(AIndex: Integer): Integer;
    function WordOf(AIndex: Integer): string;
    /// <summary>Kopf eines Klassen-, Record- oder Interface-Rumpfs ab dem Schlüsselwort AWord an AIndex; AEnd ist
    /// sein letztes Token. False bei Vorwärtsdeklaration, "class of" usw.</summary>
    function TypeHeaderEnd(AIndex: Integer; const AWord: string; out AEnd: Integer): Boolean;
  private
    /// <summary>Letztes Token von "helper … for Typ" ab "helper" an AHelper.</summary>
    function HelperEnd(AHelper: Integer): Integer;
    /// <summary>Schließende Klammer zur öffnenden an AOpen.</summary>
    function ClosingParenthesis(AOpen: Integer): Integer;
  end;

  /// <summary>Spalten je Zeile: vorhandene, gesetzte und die Kommentarzeilen, die der nächsten Codezeile folgen.
  /// </summary>
  TIndentLines = record
    /// <summary>Vorhandene Einrückung.</summary>
    Original: TArray<Integer>;
    /// <summary>Zielspalte oder TBlockIndenter.Keep.</summary>
    Target: TArray<Integer>;
    /// <summary>Zielspalte, sonst die vorhandene.</summary>
    Resolved: TArray<Integer>;
    Placed: TArray<Boolean>;
    /// <summary>Zeile beginnt mit einem Kommentar und folgt der nächsten Codezeile.</summary>
    Follow: TArray<Boolean>;
    /// <summary>Erstes Token der Zeile; -1 ohne.</summary>
    FirstToken: TArray<Integer>;
    procedure Init(const ATokens: TArray<TPascalToken>; const AColumns: TArray<Integer>);
    procedure Place(ALine, AColumn: Integer);
    /// <summary>Kommentarzeilen folgen der nächsten Codezeile.</summary>
    procedure FollowComments;
  private
    function FollowDelta(ALine: Integer): Integer;
  end;

  /// <summary>Grundlage des Durchlaufs: Stand, Zeilen und das Setzen der Spalte der laufenden Zeile.</summary>
  TIndentCore = class
  protected
    FTokens: TIndentTokens;
    FLines: TIndentLines;
    FStep: Integer;
    FState: TIndentState;
    FBranches: TBranchTracker;
    FIndex: Integer;
    FLine: Integer;
    /// <summary>Das laufende Token ist das erste seiner Zeile (und nicht hinter {$ELSE}).</summary>
    FFirst: Boolean;
    function StatementColumn: Integer;
    function LineColumn: Integer;
    /// <summary>Spalte der ersten Zeile der laufenden Anweisung.</summary>
    function StatementLineColumn: Integer;
    procedure Place(AColumn: Integer);
    procedure PlaceStatement;
    procedure StartStatement;
  end;

  /// <summary>Anweisungen: Blöcke, Verzweigungen und Symbole.</summary>
  TStatementIndenter = class(TIndentCore)
  private
    procedure CloseElse;
    procedure CloseTryPart;
    procedure CloseRepeat;
    procedure OpenRoutineBody(AKind: TFrameKind);
    function BeginColumn: Integer;
    procedure OpenBegin;
    procedure OpenAsm;
    procedure OpenTry(const AWord: string);
    procedure CloseRoutine;
    procedure CloseBlock(const AFrame: TFrame);
    function CaseWord(const AWord: string): Boolean;
    function OfWord(const AWord: string): Boolean;
    function PendingWord(const AWord: string): Boolean;
    procedure OpenBracket(const AText: string);
    procedure CloseBracket(const AText: string; ABase: Integer);
    procedure EndStatement(ABase: Integer);
    function CaseLabel(const AText: string; ABase: Integer): Boolean;
  protected
    procedure CloseEnd;
    /// <summary>end, else, finally, except, until, begin, asm, try und repeat.</summary>
    function BlockWord(const AWord: string): Boolean;
    /// <summary>case, of, then und do.</summary>
    function StatementWord(const AWord: string): Boolean;
    procedure Symbol(const AText: string);
  end;

  /// <summary>Deklarationen und der Durchlauf über die Tokens.</summary>
  TIndenter = class(TStatementIndenter)
  private
    function OpenInit(const AWord: string): Boolean;
    function OpenUnitPart(const AWord: string): Boolean;
    function UnitHeader(const AWord: string): Boolean;
    function IsSectionWord(const AWord: string): Boolean;
    function CanOpenSection: Boolean;
    function SectionColumn: Integer;
    function OpenSection(const AWord: string): Boolean;
    function Visibility(const AWord: string): Boolean;
    procedure AnonymousRoutine;
    procedure RoutineHeader;
    function RoutineWord(const AWord: string): Boolean;
    function ClassPrefixWord(const AWord: string): Boolean;
    function HeaderDirective(const AWord: string): Boolean;
    function TypeBody(const AWord: string): Boolean;
    /// <summary>Teile der Unit, Abschnitte und Sichtbarkeiten.</summary>
    function DeclarationWord(const AWord: string): Boolean;
    /// <summary>Routinenköpfe, "class" davor, Direktiven und Typrümpfe.</summary>
    function MemberWord(const AWord: string): Boolean;
    procedure PlainWord(const AWord: string);
    procedure Word(const AWord: string);
    procedure CodeToken(const AToken: TPascalToken);
    procedure Step(AIndex: Integer);
  public
    function Run(const ATokens: TArray<TPascalToken>; const AColumns: TArray<Integer>;
      AIndentSize: Integer): TArray<Integer>;
  end;

const
  SectionWords: array[0..8] of string = ('uses', 'type', 'const', 'var', 'resourcestring', 'threadvar', 'label',
    'exports', 'contains');
  VisibilityWords: array[0..5] of string = ('private', 'protected', 'public', 'published', 'automated', 'strict');
  RoutineWords: array[0..4] of string = ('procedure', 'function', 'constructor', 'destructor', 'operator');
  DirectiveWords: array[0..26] of string = ('static', 'overload', 'virtual', 'abstract', 'override',
    'reintroduce', 'inline', 'stdcall', 'cdecl', 'register', 'safecall', 'pascal', 'dynamic', 'message',
    'deprecated', 'platform', 'experimental', 'final', 'assembler', 'varargs', 'external', 'forward', 'export',
    'dispid', 'default', 'delayed', 'winapi');
  /// <summary>Blöcke, die ein end schließt.</summary>
  cEndBlocks: TFrameKinds = [TFrameKind.Block, TFrameKind.TryBlock, TFrameKind.CaseBlock, TFrameKind.AsmBlock,
    TFrameKind.InitBlock, TFrameKind.ClassBody];

{ TIndentState }

procedure TIndentState.Push(AKind: TFrameKind; AColumn: Integer);
var
  mFrame: TFrame;
begin
  mFrame := Default(TFrame);
  mFrame.Kind := AKind;
  mFrame.Column := Max(AColumn, 0);
  mFrame.Depth := Depth;
  if Count = Length(Frames) then
  begin
    SetLength(Frames, Count * 2 + 8);
  end;
  Frames[Count] := mFrame;
  Inc(Count);
end;

procedure TIndentState.Pop;
begin
  // Der unterste Rahmen (Datei) bleibt.
  if Count > 1 then
  begin
    Dec(Count);
  end;
end;

procedure TIndentState.PopAll;
begin
  Count := Min(Count, 1);
end;

procedure TIndentState.PopUntil(AKinds: TFrameKinds);
begin
  while (Count > 1) and not (TopKind in AKinds) do
  begin
    Pop;
  end;
end;

procedure TIndentState.PopPending;
begin
  while (Count > 1) and IsPending(TopKind) do
  begin
    Pop;
  end;
end;

procedure TIndentState.PopSections;
begin
  while (Count > 1) and (TopKind = TFrameKind.Section) do
  begin
    Pop;
  end;
end;

function TIndentState.TopKind: TFrameKind;
begin
  Result := Frames[Count - 1].Kind;
end;

function TIndentState.TopFrame: TFrame;
begin
  Result := Frames[Count - 1];
end;

class function TIndentState.IsPending(AKind: TFrameKind): Boolean;
begin
  Result := AKind in [TFrameKind.IfPending, TFrameKind.ElsePending, TFrameKind.DoPending,
    TFrameKind.LabelPending];
end;

function TIndentState.DeclIndex: Integer;
begin
  Result := Count - 1;
  while (Result > 0) and (Frames[Result].Kind = TFrameKind.Section) do
  begin
    Dec(Result);
  end;
end;

function TIndentState.DeclKind: TFrameKind;
begin
  Result := Frames[DeclIndex].Kind;
end;

function TIndentState.InStatements: Boolean;
begin
  Result := TopKind in [TFrameKind.Block, TFrameKind.TryBlock, TFrameKind.RepeatBlock, TFrameKind.InitBlock,
    TFrameKind.IfPending, TFrameKind.ElsePending, TFrameKind.DoPending, TFrameKind.LabelPending];
  if (TopKind = TFrameKind.CaseBlock) and not TopFrame.Variant then
  begin
    Result := True;
  end;
end;

function TIndentState.Copied: TIndentState;
begin
  Result := Self;
  Result.Frames := Copy(Frames);
end;

{ TBranchTracker }

/// <summary>Name der Direktive in Großbuchstaben, ohne "{$" bzw. "(*$".</summary>
function DirectiveName(const AText: string): string;
begin
  Result := UpperCase(AText);
  if StartsStr('(*$', Result) then
  begin
    Result := Copy(Result, 4, MaxInt);
  end
  else
  begin
    Result := Copy(Result, 3, MaxInt);
  end;
end;

procedure TBranchTracker.Directive(const AToken: TPascalToken; var AState: TIndentState);
var
  mName: string;
  mBranch: TBranch;
begin
  mName := DirectiveName(AToken.Text);
  if StartsStr('IF', mName) and not StartsStr('IFEND', mName) then
  begin
    mBranch.Saved := AState.Copied;
    mBranch.FirstEnd := mBranch.Saved;
    mBranch.Alternative := False;
    Branches := Branches + [mBranch];
  end
  else if StartsStr('ELSE', mName) and (Branches <> nil) then
  begin
    OtherBranch(AState);
  end
  else if (StartsStr('ENDIF', mName) or StartsStr('IFEND', mName)) and (Branches <> nil) then
  begin
    EndBranch(AState);
  end;
end;

procedure TBranchTracker.OtherBranch(var AState: TIndentState);
var
  mLast: Integer;
begin
  mLast := High(Branches);
  if not Branches[mLast].Alternative then
  begin
    Branches[mLast].FirstEnd := AState.Copied;
    Branches[mLast].Alternative := True;
    Inc(Alternatives);
  end;
  AState := Branches[mLast].Saved.Copied;
end;

procedure TBranchTracker.EndBranch(var AState: TIndentState);
var
  mLast: Integer;
begin
  mLast := High(Branches);
  if Branches[mLast].Alternative then
  begin
    AState := Branches[mLast].FirstEnd.Copied;
    Dec(Alternatives);
  end;
  SetLength(Branches, mLast);
end;

{ TIndentTokens }

function TIndentTokens.NextSignificant(AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(Tokens)) and (Tokens[Result].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
  begin
    Inc(Result);
  end;
end;

function TIndentTokens.PreviousSignificant(AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and (Tokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(Result);
  end;
end;

function TIndentTokens.WordOf(AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex > High(Tokens)) then
  begin
    Exit('');
  end;
  Result := LowerCase(Tokens[AIndex].Text);
end;

function TIndentTokens.HelperEnd(AHelper: Integer): Integer;
var
  mNext: Integer;
begin
  mNext := AHelper;
  while (mNext <= High(Tokens)) and (WordOf(mNext) <> 'for') do
  begin
    mNext := NextSignificant(mNext);
  end;
  Result := NextSignificant(mNext);
  while WordOf(NextSignificant(Result)) = '.' do
  begin
    Result := NextSignificant(NextSignificant(Result));
  end;
end;

function TIndentTokens.ClosingParenthesis(AOpen: Integer): Integer;
var
  mNext, mDepth: Integer;
begin
  mDepth := 0;
  mNext := AOpen;
  repeat
    if WordOf(mNext) = '(' then
    begin
      Inc(mDepth);
    end
    else if WordOf(mNext) = ')' then
    begin
      Dec(mDepth);
    end;
    Result := mNext;
    mNext := NextSignificant(mNext);
  until (mDepth = 0) or (mNext > High(Tokens));
end;

function TIndentTokens.TypeHeaderEnd(AIndex: Integer; const AWord: string; out AEnd: Integer): Boolean;
var
  mNext: Integer;
begin
  AEnd := AIndex;
  mNext := NextSignificant(AIndex);
  if MatchStr(WordOf(mNext), ['of', ';', '>', ',', ')', '=']) then
  begin
    Exit(False);
  end;
  if AWord <> 'record' then
  begin
    while MatchStr(WordOf(mNext), ['abstract', 'sealed']) do
    begin
      AEnd := mNext;
      mNext := NextSignificant(mNext);
    end;
  end;
  Result := True;
  if WordOf(mNext) = 'helper' then
  begin
    AEnd := HelperEnd(mNext);
  end
  else if (AWord <> 'record') and (WordOf(mNext) = '(') then
  begin
    // Vorfahren; "class(TBasis);" ist eine Kurzform ohne Rumpf.
    AEnd := ClosingParenthesis(mNext);
    Result := WordOf(NextSignificant(AEnd)) <> ';';
  end;
end;

{ TIndentLines }

procedure TIndentLines.Init(const ATokens: TArray<TPascalToken>; const AColumns: TArray<Integer>);
var
  mIndex, mLine: Integer;
begin
  Original := AColumns;
  SetLength(Target, Length(AColumns));
  SetLength(Resolved, Length(AColumns));
  SetLength(Placed, Length(AColumns));
  SetLength(Follow, Length(AColumns));
  SetLength(FirstToken, Length(AColumns));
  for mLine := 0 to High(AColumns) do
  begin
    Target[mLine] := TBlockIndenter.Keep;
    Resolved[mLine] := AColumns[mLine];
    FirstToken[mLine] := -1;
  end;
  for mIndex := 0 to High(ATokens) do
  begin
    mLine := ATokens[mIndex].StartPos.Line;
    if (mLine <= High(FirstToken)) and (FirstToken[mLine] < 0) then
    begin
      FirstToken[mLine] := mIndex;
    end;
  end;
end;

procedure TIndentLines.Place(ALine, AColumn: Integer);
begin
  Target[ALine] := Max(AColumn, 0);
  Resolved[ALine] := Target[ALine];
  Placed[ALine] := True;
end;

/// <summary>Verschiebung der nächsten gesetzten Codezeile nach ALine; 0 ohne.</summary>
function TIndentLines.FollowDelta(ALine: Integer): Integer;
var
  mNext: Integer;
begin
  mNext := ALine + 1;
  while (mNext <= High(Follow)) and not Placed[mNext] and (FirstToken[mNext] < 0) do
  begin
    Inc(mNext);
  end;
  Result := 0;
  if (mNext <= High(Follow)) and Placed[mNext] then
  begin
    Result := Resolved[mNext] - Original[mNext];
  end;
end;

procedure TIndentLines.FollowComments;
var
  mLine, mDelta: Integer;
begin
  for mLine := High(Follow) downto 0 do
  begin
    if Follow[mLine] and not Placed[mLine] then
    begin
      mDelta := FollowDelta(mLine);
      if mDelta <> 0 then
      begin
        Place(mLine, Original[mLine] + mDelta);
      end;
    end;
  end;
end;

{ TIndentCore }

function TIndentCore.StatementColumn: Integer;
var
  mFrame: TFrame;
begin
  mFrame := FState.TopFrame;
  case mFrame.Kind of
    TFrameKind.Top:
      Result := 0;
    TFrameKind.Routine:
      if mFrame.Anonymous then
      begin
        Result := mFrame.Column + FStep;
      end
      else
      begin
        Result := mFrame.Column;
      end;
  else
    Result := mFrame.Column + FStep;
  end;
end;

function TIndentCore.LineColumn: Integer;
begin
  Result := FLines.Resolved[FLine];
end;

function TIndentCore.StatementLineColumn: Integer;
begin
  Result := FLines.Resolved[Max(FState.StmtLine, 0)];
end;

procedure TIndentCore.Place(AColumn: Integer);
begin
  if FFirst then
  begin
    FLines.Place(FLine, AColumn);
  end;
end;

procedure TIndentCore.PlaceStatement;
var
  mDelta: Integer;
begin
  if not FFirst then
  begin
    Exit;
  end;
  if FState.AtStart then
  begin
    Place(StatementColumn);
    Exit;
  end;
  // Fortsetzung: Abstand zur ersten Zeile der Anweisung bleibt.
  mDelta := 0;
  if (FState.StmtLine >= 0) and (FState.StmtLine < FLine) then
  begin
    mDelta := FLines.Resolved[FState.StmtLine] - FLines.Original[FState.StmtLine];
  end;
  Place(FLines.Original[FLine] + mDelta);
end;

procedure TIndentCore.StartStatement;
begin
  if not FState.AtStart then
  begin
    Exit;
  end;
  FState.StmtLine := FLine;
  FState.AtStart := False;
  FState.AfterHeader := False;
  if (FState.TopKind = TFrameKind.CaseBlock) and not FState.TopFrame.InElse then
  begin
    FState.Frames[FState.Count - 1].InLabel := True;
  end;
end;

{ TStatementIndenter }

procedure TStatementIndenter.CloseElse;
var
  mColumn: Integer;
begin
  while (FState.Count > 1) and TIndentState.IsPending(FState.TopKind) do
  begin
    if FState.TopKind = TFrameKind.IfPending then
    begin
      mColumn := FState.TopFrame.Column;
      FState.Pop;
      Place(mColumn);
      FState.Push(TFrameKind.ElsePending, mColumn);
      FState.AtStart := True;
      Exit;
    end;
    FState.Pop;
  end;
  if FState.TopKind = TFrameKind.CaseBlock then
  begin
    FState.Frames[FState.Count - 1].InElse := True;
    FState.Frames[FState.Count - 1].InLabel := False;
  end;
  Place(FState.TopFrame.Column);
  FState.AtStart := True;
end;

procedure TStatementIndenter.CloseTryPart;
begin
  FState.PopUntil([TFrameKind.TryBlock, TFrameKind.Routine]);
  Place(FState.TopFrame.Column);
  FState.AtStart := True;
end;

procedure TStatementIndenter.CloseRepeat;
begin
  FState.PopUntil([TFrameKind.RepeatBlock, TFrameKind.Routine]);
  Place(FState.TopFrame.Column);
  if FState.TopKind = TFrameKind.RepeatBlock then
  begin
    FState.Pop;
  end;
  FState.StmtLine := FLine;
  FState.AtStart := False;
end;

/// <summary>begin bzw. asm einer Routine öffnen ihren Rumpf.</summary>
procedure TStatementIndenter.OpenRoutineBody(AKind: TFrameKind);
begin
  FState.PopSections;
  Place(FState.TopFrame.Column);
  FState.Frames[FState.Count - 1].HasBody := True;
  FState.Push(AKind, FState.TopFrame.Column);
end;

/// <summary>Spalte eines begin am Anfang einer Anweisung.</summary>
function TStatementIndenter.BeginColumn: Integer;
var
  mFrame: TFrame;
begin
  mFrame := FState.TopFrame;
  if mFrame.Kind in [TFrameKind.IfPending, TFrameKind.ElsePending, TFrameKind.DoPending] then
  begin
    Result := mFrame.Column;
  end
  else if mFrame.Kind = TFrameKind.Top then
  begin
    Result := 0;
  end
  else
  begin
    Result := StatementColumn;
  end;
end;

procedure TStatementIndenter.OpenBegin;
var
  mDecl: TFrame;
  mColumn: Integer;
begin
  mDecl := FState.Frames[FState.DeclIndex];
  if (mDecl.Kind = TFrameKind.Routine) and not mDecl.HasBody and not mDecl.NoBody then
  begin
    OpenRoutineBody(TFrameKind.Block);
  end
  else if FState.AtStart then
  begin
    if FState.DeclKind = TFrameKind.Top then
    begin
      FState.PopSections;
    end;
    mColumn := BeginColumn;
    Place(mColumn);
    FState.Push(TFrameKind.Block, mColumn);
  end
  else
  begin
    PlaceStatement;
    FState.Push(TFrameKind.Block, LineColumn);
  end;
  FState.AtStart := True;
end;

procedure TStatementIndenter.OpenAsm;
var
  mDecl: TFrame;
begin
  mDecl := FState.Frames[FState.DeclIndex];
  if (mDecl.Kind = TFrameKind.Routine) and not mDecl.HasBody then
  begin
    OpenRoutineBody(TFrameKind.AsmBlock);
    Exit;
  end;
  PlaceStatement;
  StartStatement;
  FState.Push(TFrameKind.AsmBlock, LineColumn);
end;

procedure TStatementIndenter.OpenTry(const AWord: string);
begin
  PlaceStatement;
  StartStatement;
  if AWord = 'try' then
  begin
    FState.Push(TFrameKind.TryBlock, LineColumn);
  end
  else
  begin
    FState.Push(TFrameKind.RepeatBlock, LineColumn);
  end;
  FState.AtStart := True;
end;

/// <summary>Das Ende des Rumpfs schließt die Routine; bei einer anonymen Methode gilt wieder die umgebende
/// Anweisung.</summary>
procedure TStatementIndenter.CloseRoutine;
var
  mFrame: TFrame;
begin
  mFrame := FState.TopFrame;
  FState.Pop;
  if mFrame.Anonymous then
  begin
    FState.StmtLine := mFrame.OuterStmtLine;
    FState.PendingCase := mFrame.OuterPendingCase;
    FState.CaseColumn := mFrame.OuterCaseColumn;
  end;
end;

procedure TStatementIndenter.CloseBlock(const AFrame: TFrame);
begin
  Place(AFrame.Column);
  FState.Pop;
  if (AFrame.Kind in [TFrameKind.Block, TFrameKind.AsmBlock]) and (FState.TopKind = TFrameKind.Routine) and
    FState.TopFrame.HasBody then
  begin
    CloseRoutine;
  end;
  FState.AtStart := False;
end;

procedure TStatementIndenter.CloseEnd;
var
  mFrame: TFrame;
begin
  FState.PopPending;
  while FState.Count > 1 do
  begin
    mFrame := FState.TopFrame;
    // Der variante Teil eines Records hat kein eigenes end.
    if (mFrame.Kind in cEndBlocks) and not ((mFrame.Kind = TFrameKind.CaseBlock) and mFrame.Variant) then
    begin
      CloseBlock(mFrame);
      Exit;
    end;
    FState.Pop;
  end;
  Place(0);
  FState.AtStart := False;
end;

function TStatementIndenter.BlockWord(const AWord: string): Boolean;
begin
  Result := True;
  if AWord = 'end' then
  begin
    CloseEnd;
  end
  else if AWord = 'else' then
  begin
    CloseElse;
  end
  else if MatchStr(AWord, ['finally', 'except']) then
  begin
    CloseTryPart;
  end
  else if AWord = 'until' then
  begin
    CloseRepeat;
  end
  else if AWord = 'begin' then
  begin
    OpenBegin;
  end
  else if AWord = 'asm' then
  begin
    OpenAsm;
  end
  else if MatchStr(AWord, ['try', 'repeat']) then
  begin
    OpenTry(AWord);
  end
  else
  begin
    Result := False;
  end;
end;

function TStatementIndenter.CaseWord(const AWord: string): Boolean;
begin
  Result := (AWord = 'case') and not FState.PendingCase;
  if Result then
  begin
    PlaceStatement;
    StartStatement;
    FState.PendingCase := True;
    FState.CaseColumn := FLines.Resolved[FState.StmtLine];
  end;
end;

function TStatementIndenter.OfWord(const AWord: string): Boolean;
begin
  Result := (AWord = 'of') and FState.PendingCase and (FState.Depth = FState.TopFrame.Depth);
  if not Result then
  begin
    Exit;
  end;
  PlaceStatement;
  FState.PendingCase := False;
  FState.Push(TFrameKind.CaseBlock, FState.CaseColumn);
  if FState.DeclKind = TFrameKind.ClassBody then
  begin
    FState.Frames[FState.Count - 1].Variant := True;
  end;
  FState.AtStart := True;
end;

/// <summary>then und do: die folgende Anweisung rückt ein, bis sie endet.</summary>
function TStatementIndenter.PendingWord(const AWord: string): Boolean;
var
  mKind: TFrameKind;
begin
  Result := True;
  if AWord = 'then' then
  begin
    mKind := TFrameKind.IfPending;
  end
  else if AWord = 'do' then
  begin
    mKind := TFrameKind.DoPending;
  end
  else
  begin
    Exit(False);
  end;
  PlaceStatement;
  FState.Push(mKind, StatementLineColumn);
  FState.AtStart := True;
end;

function TStatementIndenter.StatementWord(const AWord: string): Boolean;
begin
  Result := CaseWord(AWord) or OfWord(AWord) or PendingWord(AWord);
end;

procedure TStatementIndenter.OpenBracket(const AText: string);
begin
  if FState.AtStart and (AText = '[') and not FState.InStatements then
  begin
    FState.Attribute := True;
  end;
  PlaceStatement;
  StartStatement;
  Inc(FState.Depth);
end;

procedure TStatementIndenter.CloseBracket(const AText: string; ABase: Integer);
begin
  PlaceStatement;
  if FState.Depth > 0 then
  begin
    Dec(FState.Depth);
  end;
  if FState.Attribute and (AText = ']') and (FState.Depth = ABase) then
  begin
    FState.Attribute := False;
    FState.AtStart := True;
  end;
end;

/// <summary>; auf der Klammertiefe des Rahmens: Routinenkopf öffnet die Routine, forward/external schließt sie,
/// sonst enden offene if/else/do.</summary>
procedure TStatementIndenter.EndStatement(ABase: Integer);
begin
  FState.Depth := ABase;
  FState.Attribute := False;
  FState.PendingCase := False;
  if FState.PendingRoutine then
  begin
    FState.PendingRoutine := False;
    FState.PopSections;
    FState.Push(TFrameKind.Routine, FState.RoutineColumn);
  end
  else if (FState.TopKind = TFrameKind.Routine) and FState.TopFrame.NoBody then
  begin
    FState.Pop;
  end
  else
  begin
    FState.PopPending;
  end;
  FState.AtStart := True;
end;

/// <summary>: hinter der Marke eines case-Zweigs.</summary>
function TStatementIndenter.CaseLabel(const AText: string; ABase: Integer): Boolean;
begin
  Result := (AText = ':') and (FState.TopKind = TFrameKind.CaseBlock) and FState.TopFrame.InLabel and
    (FState.Depth = ABase);
  if Result then
  begin
    FState.Frames[FState.Count - 1].InLabel := False;
    FState.Push(TFrameKind.LabelPending, StatementLineColumn);
    FState.AtStart := True;
  end;
end;

procedure TStatementIndenter.Symbol(const AText: string);
var
  mBase: Integer;
begin
  mBase := FState.TopFrame.Depth;
  if (AText = '(') or (AText = '[') then
  begin
    OpenBracket(AText);
  end
  else if (AText = ')') or (AText = ']') then
  begin
    CloseBracket(AText, mBase);
  end
  else
  begin
    PlaceStatement;
    if (AText = ';') and (FState.Depth <= mBase) then
    begin
      EndStatement(mBase);
    end
    else if not CaseLabel(AText, mBase) then
    begin
      StartStatement;
    end;
  end;
end;

{ TIndenter }

function TIndenter.OpenInit(const AWord: string): Boolean;
begin
  Result := MatchStr(AWord, ['initialization', 'finalization']);
  if Result then
  begin
    FState.PopAll;
    Place(0);
    FState.Push(TFrameKind.InitBlock, 0);
    FState.AtStart := True;
  end;
end;

/// <summary>implementation bzw. interface als Teil der Unit (nicht als Typ).</summary>
function TIndenter.OpenUnitPart(const AWord: string): Boolean;
begin
  Result := (AWord = 'implementation') or ((AWord = 'interface') and FState.AtStart and
    (FState.DeclKind = TFrameKind.Top));
  if not Result then
  begin
    Exit;
  end;
  FState.PopAll;
  Place(0);
  if AWord = 'implementation' then
  begin
    FState.InImplementation := True;
  end;
  FState.AtStart := True;
end;

function TIndenter.UnitHeader(const AWord: string): Boolean;
begin
  Result := MatchStr(AWord, ['unit', 'program', 'library', 'package']) and FState.AtStart and (FState.Count = 1);
  if not Result then
  begin
    Exit;
  end;
  Place(0);
  if AWord <> 'unit' then
  begin
    FState.HasBodies := AWord <> 'package';
  end;
  StartStatement;
end;

function TIndenter.IsSectionWord(const AWord: string): Boolean;
begin
  Result := MatchStr(AWord, SectionWords) or ((AWord = 'requires') and (FState.DeclKind = TFrameKind.Top));
end;

/// <summary>Abschnitte stehen in der Unit, einer Routine oder einem Klassenrumpf; in Anweisungen sind var und const
/// Inline-Deklarationen.</summary>
function TIndenter.CanOpenSection: Boolean;
var
  mDecl: TFrameKind;
begin
  mDecl := FState.DeclKind;
  Result := not FState.InStatements and (mDecl in [TFrameKind.Top, TFrameKind.Routine, TFrameKind.ClassBody]) and
    (FState.AtStart or ((mDecl = TFrameKind.Routine) and FState.Frames[FState.DeclIndex].Anonymous));
end;

function TIndenter.SectionColumn: Integer;
var
  mFrame: TFrame;
begin
  mFrame := FState.TopFrame;
  case mFrame.Kind of
    TFrameKind.Top:
      Result := 0;
    TFrameKind.Routine:
      Result := mFrame.Column;
  else
    Result := mFrame.Column + FStep;
  end;
end;

/// <summary>Abschnitte: uses, type, const, var usw.</summary>
function TIndenter.OpenSection(const AWord: string): Boolean;
var
  mColumn: Integer;
begin
  Result := IsSectionWord(AWord) and CanOpenSection;
  if not Result then
  begin
    Exit;
  end;
  FState.PopSections;
  if FFirst then
  begin
    mColumn := SectionColumn;
    Place(mColumn);
  end
  else
  begin
    mColumn := LineColumn;
  end;
  FState.Push(TFrameKind.Section, mColumn);
  FState.AtStart := True;
  FState.ClassPrefix := False;
end;

function TIndenter.Visibility(const AWord: string): Boolean;
begin
  Result := MatchStr(AWord, VisibilityWords) and FState.AtStart and (FState.DeclKind = TFrameKind.ClassBody);
  if Result then
  begin
    FState.PopSections;
    Place(FState.TopFrame.Column);
    FState.AtStart := True;
  end;
end;

/// <summary>Anonyme Methode in einer Anweisung; nach ihrem end gilt wieder die umgebende Anweisung.</summary>
procedure TIndenter.AnonymousRoutine;
var
  mColumn: Integer;
begin
  PlaceStatement;
  StartStatement;
  mColumn := LineColumn;
  if not FFirst then
  begin
    Inc(mColumn, FStep);
  end;
  FState.Push(TFrameKind.Routine, mColumn);
  FState.Frames[FState.Count - 1].Anonymous := True;
  FState.Frames[FState.Count - 1].OuterStmtLine := FState.StmtLine;
  FState.Frames[FState.Count - 1].OuterPendingCase := FState.PendingCase;
  FState.Frames[FState.Count - 1].OuterCaseColumn := FState.CaseColumn;
  FState.PendingCase := False;
end;

/// <summary>Kopf einer Routine; hat sie einen Rumpf, öffnet sie beim ; des Kopfes.</summary>
procedure TIndenter.RoutineHeader;
var
  mColumn: Integer;
  mFrame: TFrame;
begin
  if FState.ClassPrefix then
  begin
    mColumn := FLines.Resolved[FState.StmtLine];
  end
  else
  begin
    FState.PopSections;
    mColumn := 0;
    if FState.TopKind <> TFrameKind.Top then
    begin
      mColumn := FState.TopFrame.Column + FStep;
    end;
    Place(mColumn);
    FState.StmtLine := FLine;
    FState.AtStart := False;
  end;
  FState.AfterHeader := True;
  FState.ClassPrefix := False;
  mFrame := FState.TopFrame;
  if ((mFrame.Kind = TFrameKind.Top) and (FState.InImplementation or FState.HasBodies)) or
    ((mFrame.Kind = TFrameKind.Routine) and not mFrame.HasBody) then
  begin
    FState.PendingRoutine := True;
    FState.RoutineColumn := mColumn;
  end;
end;

function TIndenter.RoutineWord(const AWord: string): Boolean;
begin
  Result := False;
  if not MatchStr(AWord, RoutineWords) or ((AWord = 'operator') and not FState.ClassPrefix) then
  begin
    Exit;
  end;
  if FState.InStatements then
  begin
    AnonymousRoutine;
    Exit(True);
  end;
  Result := FState.AtStart or FState.ClassPrefix;
  if Result then
  begin
    RoutineHeader;
  end;
end;

/// <summary>"class" vor einer Routine, var, property oder threadvar.</summary>
function TIndenter.ClassPrefixWord(const AWord: string): Boolean;
var
  mNext: string;
  mRoutine: Boolean;
begin
  Result := False;
  if (AWord <> 'class') or not FState.AtStart or FState.InStatements then
  begin
    Exit;
  end;
  mNext := FTokens.WordOf(FTokens.NextSignificant(FIndex));
  mRoutine := MatchStr(mNext, RoutineWords);
  if not mRoutine and not MatchStr(mNext, ['var', 'property', 'threadvar']) then
  begin
    Exit;
  end;
  if mRoutine then
  begin
    FState.PopSections;
  end;
  PlaceStatement;
  StartStatement;
  FState.ClassPrefix := mRoutine;
  FState.AfterHeader := True;
  Result := True;
end;

/// <summary>Direktiven setzen den Kopf fort: Abstand zu dessen erster Zeile.</summary>
function TIndenter.HeaderDirective(const AWord: string): Boolean;
begin
  Result := FState.AtStart and FState.AfterHeader and MatchStr(AWord, DirectiveWords) and not FState.InStatements;
  if not Result then
  begin
    Exit;
  end;
  if MatchStr(AWord, ['forward', 'external']) and (FState.TopKind = TFrameKind.Routine) and
    not FState.TopFrame.HasBody and not FState.TopFrame.Anonymous then
  begin
    FState.Frames[FState.Count - 1].NoBody := True;
  end;
  FState.AtStart := False;
  PlaceStatement;
end;

/// <summary>Rümpfe von Klassen, Records und Interfaces hinter "=" (Records auch hinter ":").</summary>
function TIndenter.TypeBody(const AWord: string): Boolean;
var
  mIndex, mHeaderEnd: Integer;
  mPrevious: string;
begin
  Result := False;
  if not MatchStr(AWord, ['class', 'record', 'object', 'interface', 'dispinterface']) then
  begin
    Exit;
  end;
  mIndex := FTokens.PreviousSignificant(FIndex);
  if FTokens.WordOf(mIndex) = 'packed' then
  begin
    mIndex := FTokens.PreviousSignificant(mIndex);
  end;
  mPrevious := FTokens.WordOf(mIndex);
  if ((mPrevious <> '=') and ((mPrevious <> ':') or (AWord <> 'record'))) or
    not FTokens.TypeHeaderEnd(FIndex, AWord, mHeaderEnd) then
  begin
    Exit;
  end;
  PlaceStatement;
  StartStatement;
  if FState.StmtLine >= 0 then
  begin
    FState.Push(TFrameKind.ClassBody, FLines.Resolved[FState.StmtLine]);
  end
  else
  begin
    FState.Push(TFrameKind.ClassBody, LineColumn);
  end;
  FState.HeaderEnd := mHeaderEnd;
  Result := True;
end;

function TIndenter.DeclarationWord(const AWord: string): Boolean;
begin
  Result := OpenInit(AWord) or OpenUnitPart(AWord) or UnitHeader(AWord) or OpenSection(AWord) or Visibility(AWord);
end;

function TIndenter.MemberWord(const AWord: string): Boolean;
begin
  Result := RoutineWord(AWord) or ClassPrefixWord(AWord) or HeaderDirective(AWord) or TypeBody(AWord);
end;

procedure TIndenter.PlainWord(const AWord: string);
begin
  PlaceStatement;
  StartStatement;
  if AWord = 'property' then
  begin
    FState.AfterHeader := True;
  end;
end;

procedure TIndenter.Word(const AWord: string);
begin
  if not (BlockWord(AWord) or DeclarationWord(AWord) or MemberWord(AWord) or StatementWord(AWord)) then
  begin
    PlainWord(AWord);
  end;
end;

procedure TIndenter.CodeToken(const AToken: TPascalToken);
begin
  if AToken.Kind in [TPascalTokenKind.Keyword, TPascalTokenKind.Identifier] then
  begin
    Word(LowerCase(AToken.Text));
  end
  else if AToken.Kind = TPascalTokenKind.Symbol then
  begin
    Symbol(AToken.Text);
  end
  else
  begin
    PlaceStatement;
    StartStatement;
  end;
  if FIndex = FState.HeaderEnd then
  begin
    FState.HeaderEnd := -1;
    FState.AtStart := True;
  end;
end;

procedure TIndenter.Step(AIndex: Integer);
var
  mToken: TPascalToken;
begin
  mToken := FTokens.Tokens[AIndex];
  FIndex := AIndex;
  FLine := mToken.StartPos.Line;
  FFirst := (FLines.FirstToken[FLine] = AIndex) and (FBranches.Alternatives = 0);
  if mToken.Kind = TPascalTokenKind.Directive then
  begin
    FBranches.Directive(mToken, FState);
  end
  else if mToken.Kind = TPascalTokenKind.Comment then
  begin
    FLines.Follow[FLine] := FLines.Follow[FLine] or (FFirst and (FState.TopKind <> TFrameKind.AsmBlock));
  end
  else if FState.TopKind <> TFrameKind.AsmBlock then
  begin
    CodeToken(mToken);
  end
  else if (mToken.Kind = TPascalTokenKind.Keyword) and mToken.IsKeyword('end') then
  begin
    CloseEnd;
  end;
end;

function TIndenter.Run(const ATokens: TArray<TPascalToken>; const AColumns: TArray<Integer>;
  AIndentSize: Integer): TArray<Integer>;
var
  mIndex: Integer;
begin
  FTokens.Tokens := ATokens;
  FStep := Max(AIndentSize, 1);
  FLines.Init(ATokens, AColumns);
  FState := Default(TIndentState);
  FState.StmtLine := -1;
  FState.HeaderEnd := -1;
  FState.AtStart := True;
  FState.Push(TFrameKind.Top, 0);
  FBranches := Default(TBranchTracker);
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].StartPos.Line > High(FLines.FirstToken) then
    begin
      Break;
    end;
    Step(mIndex);
  end;
  FLines.FollowComments;
  Result := FLines.Target;
end;

{ TBlockIndenter }

class function TBlockIndenter.Columns(const ATokens: TArray<TPascalToken>; const AColumns: TArray<Integer>;
  AIndentSize: Integer): TArray<Integer>;
var
  mIndenter: TIndenter;
begin
  mIndenter := TIndenter.Create;
  try
    Result := mIndenter.Run(ATokens, AColumns, AIndentSize);
  finally
    mIndenter.Free;
  end;
end;

end.
