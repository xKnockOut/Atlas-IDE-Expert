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
  end;

  TBranch = record
    Saved: TIndentState;
    FirstEnd: TIndentState;
    Alternative: Boolean;
  end;

  TIndenter = class
  private
    FTokens: TArray<TPascalToken>;
    FOriginal: TArray<Integer>;
    FResult: TArray<Integer>;
    FResolved: TArray<Integer>;
    FPlaced: TArray<Boolean>;
    FFollow: TArray<Boolean>;
    FFirstToken: TArray<Integer>;
    FStep: Integer;
    S: TIndentState;
    FBranches: TArray<TBranch>;
    FAlternatives: Integer;
    FIndex: Integer;
    FLine: Integer;
    FFirst: Boolean;
    procedure Push(AKind: TFrameKind; AColumn: Integer);
    procedure Pop;
    function TopKind: TFrameKind;
    function TopFrame: TFrame;
    function IsPending(AKind: TFrameKind): Boolean;
    procedure PopPending;
    procedure PopSections;
    function DeclKind: TFrameKind;
    function DeclIndex: Integer;
    function InStatements: Boolean;
    function StatementColumn: Integer;
    function LineColumn: Integer;
    function NextSignificant(AIndex: Integer): Integer;
    function WordOf(AIndex: Integer): string;
    procedure Place(AColumn: Integer);
    procedure PlaceStatement;
    procedure StartStatement;
    procedure Directive(const AToken: TPascalToken);
    function TypeHeaderEnd(AIndex: Integer; const AWord: string; out AEnd: Integer): Boolean;
    procedure Word(const AWord: string);
    procedure Symbol(const AText: string);
    procedure CloseEnd;
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

{ TIndenter }

procedure TIndenter.Push(AKind: TFrameKind; AColumn: Integer);
var
  Frame: TFrame;
begin
  Frame := Default(TFrame);
  Frame.Kind := AKind;
  Frame.Column := Max(AColumn, 0);
  Frame.Depth := S.Depth;
  if S.Count = Length(S.Frames) then
    SetLength(S.Frames, S.Count * 2 + 8);
  S.Frames[S.Count] := Frame;
  Inc(S.Count);
end;

procedure TIndenter.Pop;
begin
  // Der unterste Rahmen (Datei) bleibt.
  if S.Count > 1 then
    Dec(S.Count);
end;

function TIndenter.TopKind: TFrameKind;
begin
  Result := S.Frames[S.Count - 1].Kind;
end;

function TIndenter.TopFrame: TFrame;
begin
  Result := S.Frames[S.Count - 1];
end;

function TIndenter.IsPending(AKind: TFrameKind): Boolean;
begin
  Result := AKind in [TFrameKind.IfPending, TFrameKind.ElsePending, TFrameKind.DoPending,
    TFrameKind.LabelPending];
end;

procedure TIndenter.PopPending;
begin
  while (S.Count > 1) and IsPending(TopKind) do
    Pop;
end;

procedure TIndenter.PopSections;
begin
  while (S.Count > 1) and (TopKind = TFrameKind.Section) do
    Pop;
end;

function TIndenter.DeclIndex: Integer;
begin
  Result := S.Count - 1;
  while (Result > 0) and (S.Frames[Result].Kind = TFrameKind.Section) do
    Dec(Result);
end;

function TIndenter.DeclKind: TFrameKind;
begin
  Result := S.Frames[DeclIndex].Kind;
end;

function TIndenter.InStatements: Boolean;
begin
  Result := TopKind in [TFrameKind.Block, TFrameKind.TryBlock, TFrameKind.RepeatBlock, TFrameKind.InitBlock,
    TFrameKind.IfPending, TFrameKind.ElsePending, TFrameKind.DoPending, TFrameKind.LabelPending];
  if (TopKind = TFrameKind.CaseBlock) and not TopFrame.Variant then
    Result := True;
end;

function TIndenter.StatementColumn: Integer;
var
  Frame: TFrame;
begin
  Frame := TopFrame;
  case Frame.Kind of
    TFrameKind.Top:
      Result := 0;
    TFrameKind.Routine:
      if Frame.Anonymous then
        Result := Frame.Column + FStep
      else
        Result := Frame.Column;
  else
    Result := Frame.Column + FStep;
  end;
end;

function TIndenter.LineColumn: Integer;
begin
  Result := FResolved[FLine];
end;

function TIndenter.NextSignificant(AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(FTokens)) and (FTokens[Result].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
    Inc(Result);
end;

function TIndenter.WordOf(AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex > High(FTokens)) then
    Exit('');
  Result := LowerCase(FTokens[AIndex].Text);
end;

procedure TIndenter.Place(AColumn: Integer);
begin
  if not FFirst then
    Exit;
  FResult[FLine] := Max(AColumn, 0);
  FResolved[FLine] := Max(AColumn, 0);
  FPlaced[FLine] := True;
end;

procedure TIndenter.PlaceStatement;
var
  Delta: Integer;
begin
  if not FFirst then
    Exit;
  if S.AtStart then
    Place(StatementColumn)
  else
  begin
    // Fortsetzung: Abstand zur ersten Zeile der Anweisung bleibt.
    Delta := 0;
    if (S.StmtLine >= 0) and (S.StmtLine < FLine) then
      Delta := FResolved[S.StmtLine] - FOriginal[S.StmtLine];
    Place(FOriginal[FLine] + Delta);
  end;
end;

procedure TIndenter.StartStatement;
begin
  if S.AtStart then
  begin
    S.StmtLine := FLine;
    S.AtStart := False;
    S.AfterHeader := False;
    if (TopKind = TFrameKind.CaseBlock) and not TopFrame.InElse then
      S.Frames[S.Count - 1].InLabel := True;
  end;
end;

procedure TIndenter.Directive(const AToken: TPascalToken);
var
  Text: string;
  Branch: TBranch;
begin
  Text := UpperCase(AToken.Text);
  if StartsStr('(*$', Text) then
    Text := Copy(Text, 4, MaxInt)
  else
    Text := Copy(Text, 3, MaxInt);
  if StartsStr('IF', Text) and not StartsStr('IFEND', Text) then
  begin
    Branch.Saved := S;
    Branch.Saved.Frames := Copy(S.Frames);
    Branch.FirstEnd := Branch.Saved;
    Branch.Alternative := False;
    FBranches := FBranches + [Branch];
  end
  else if (StartsStr('ELSE', Text) or StartsStr('ELSEIF', Text)) and (FBranches <> nil) then
  begin
    if not FBranches[High(FBranches)].Alternative then
    begin
      FBranches[High(FBranches)].FirstEnd := S;
      FBranches[High(FBranches)].FirstEnd.Frames := Copy(S.Frames);
      FBranches[High(FBranches)].Alternative := True;
      Inc(FAlternatives);
    end;
    S := FBranches[High(FBranches)].Saved;
    S.Frames := Copy(S.Frames);
  end
  else if (StartsStr('ENDIF', Text) or StartsStr('IFEND', Text)) and (FBranches <> nil) then
  begin
    if FBranches[High(FBranches)].Alternative then
    begin
      S := FBranches[High(FBranches)].FirstEnd;
      S.Frames := Copy(S.Frames);
      Dec(FAlternatives);
    end;
    SetLength(FBranches, Length(FBranches) - 1);
  end;
end;

function TIndenter.TypeHeaderEnd(AIndex: Integer; const AWord: string; out AEnd: Integer): Boolean;
var
  Next, Depth: Integer;
begin
  // Kopf eines Klassen-, Record- oder Interface-Rumpfs; False bei Vorwärtsdeklaration, "class of" usw.
  AEnd := AIndex;
  Next := NextSignificant(AIndex);
  if MatchStr(WordOf(Next), ['of', ';', '>', ',', ')', '=']) then
    Exit(False);
  if AWord = 'record' then
  begin
    if WordOf(Next) = 'helper' then
    begin
      while (Next <= High(FTokens)) and (WordOf(Next) <> 'for') do
        Next := NextSignificant(Next);
      AEnd := NextSignificant(Next);
      while (WordOf(NextSignificant(AEnd)) = '.') do
        AEnd := NextSignificant(NextSignificant(AEnd));
    end;
    Exit(True);
  end;
  while MatchStr(WordOf(Next), ['abstract', 'sealed']) do
  begin
    AEnd := Next;
    Next := NextSignificant(Next);
  end;
  if WordOf(Next) = 'helper' then
  begin
    while (Next <= High(FTokens)) and (WordOf(Next) <> 'for') do
      Next := NextSignificant(Next);
    AEnd := NextSignificant(Next);
    while (WordOf(NextSignificant(AEnd)) = '.') do
      AEnd := NextSignificant(NextSignificant(AEnd));
    Exit(True);
  end;
  if WordOf(Next) = '(' then
  begin
    Depth := 0;
    repeat
      if WordOf(Next) = '(' then
        Inc(Depth)
      else if WordOf(Next) = ')' then
        Dec(Depth);
      AEnd := Next;
      Next := NextSignificant(Next);
    until (Depth = 0) or (Next > High(FTokens));
    if WordOf(Next) = ';' then
      Exit(False);
  end;
  Result := True;
end;

procedure TIndenter.CloseEnd;
var
  Kind: TFrameKind;
  Frame: TFrame;
begin
  PopPending;
  while S.Count > 1 do
  begin
    Frame := TopFrame;
    Kind := Frame.Kind;
    if (Kind = TFrameKind.CaseBlock) and Frame.Variant then
    begin
      Pop;
      Continue;
    end;
    if Kind in [TFrameKind.Block, TFrameKind.TryBlock, TFrameKind.CaseBlock, TFrameKind.AsmBlock,
      TFrameKind.InitBlock, TFrameKind.ClassBody] then
    begin
      Place(Frame.Column);
      Pop;
      // Ende des Rumpfs schließt die Routine.
      if (Kind in [TFrameKind.Block, TFrameKind.AsmBlock]) and (TopKind = TFrameKind.Routine) and
        TopFrame.HasBody then
      begin
        Frame := TopFrame;
        Pop;
        if Frame.Anonymous then
        begin
          S.StmtLine := Frame.OuterStmtLine;
          S.PendingCase := Frame.OuterPendingCase;
          S.CaseColumn := Frame.OuterCaseColumn;
        end;
      end;
      S.AtStart := False;
      Exit;
    end;
    Pop;
  end;
  Place(0);
  S.AtStart := False;
end;

procedure TIndenter.Word(const AWord: string);
var
  Frame: TFrame;
  Column, HeaderEnd, Index: Integer;
  Previous: string;
begin
  if AWord = 'end' then
  begin
    CloseEnd;
    Exit;
  end;
  if AWord = 'else' then
  begin
    while (S.Count > 1) and IsPending(TopKind) do
    begin
      if TopKind = TFrameKind.IfPending then
      begin
        Column := TopFrame.Column;
        Pop;
        Place(Column);
        Push(TFrameKind.ElsePending, Column);
        S.AtStart := True;
        Exit;
      end;
      Pop;
    end;
    if TopKind = TFrameKind.CaseBlock then
    begin
      S.Frames[S.Count - 1].InElse := True;
      S.Frames[S.Count - 1].InLabel := False;
    end;
    Place(TopFrame.Column);
    S.AtStart := True;
    Exit;
  end;
  if MatchStr(AWord, ['finally', 'except']) then
  begin
    while (S.Count > 1) and not (TopKind in [TFrameKind.TryBlock, TFrameKind.Routine]) do
      Pop;
    Place(TopFrame.Column);
    S.AtStart := True;
    Exit;
  end;
  if AWord = 'until' then
  begin
    while (S.Count > 1) and not (TopKind in [TFrameKind.RepeatBlock, TFrameKind.Routine]) do
      Pop;
    Place(TopFrame.Column);
    if TopKind = TFrameKind.RepeatBlock then
      Pop;
    S.StmtLine := FLine;
    S.AtStart := False;
    Exit;
  end;
  if AWord = 'begin' then
  begin
    Index := DeclIndex;
    if (S.Frames[Index].Kind = TFrameKind.Routine) and not S.Frames[Index].HasBody and
      not S.Frames[Index].NoBody then
    begin
      PopSections;
      Place(TopFrame.Column);
      S.Frames[S.Count - 1].HasBody := True;
      Push(TFrameKind.Block, TopFrame.Column);
    end
    else if S.AtStart then
    begin
      if DeclKind = TFrameKind.Top then
        PopSections;
      Frame := TopFrame;
      if Frame.Kind in [TFrameKind.IfPending, TFrameKind.ElsePending, TFrameKind.DoPending] then
        Column := Frame.Column
      else if Frame.Kind = TFrameKind.Top then
        Column := 0
      else
        Column := StatementColumn;
      Place(Column);
      Push(TFrameKind.Block, Column);
    end
    else
    begin
      PlaceStatement;
      Push(TFrameKind.Block, LineColumn);
    end;
    S.AtStart := True;
    Exit;
  end;
  if AWord = 'asm' then
  begin
    Index := DeclIndex;
    if (S.Frames[Index].Kind = TFrameKind.Routine) and not S.Frames[Index].HasBody then
    begin
      PopSections;
      Place(TopFrame.Column);
      S.Frames[S.Count - 1].HasBody := True;
      Push(TFrameKind.AsmBlock, TopFrame.Column);
    end
    else
    begin
      if S.AtStart then
        Place(StatementColumn)
      else
        PlaceStatement;
      StartStatement;
      Push(TFrameKind.AsmBlock, LineColumn);
    end;
    Exit;
  end;
  if MatchStr(AWord, ['try', 'repeat']) then
  begin
    PlaceStatement;
    StartStatement;
    if AWord = 'try' then
      Push(TFrameKind.TryBlock, LineColumn)
    else
      Push(TFrameKind.RepeatBlock, LineColumn);
    S.AtStart := True;
    Exit;
  end;
  if MatchStr(AWord, ['initialization', 'finalization']) then
  begin
    while S.Count > 1 do
      Pop;
    Place(0);
    Push(TFrameKind.InitBlock, 0);
    S.AtStart := True;
    Exit;
  end;
  if (AWord = 'implementation') or ((AWord = 'interface') and S.AtStart and (DeclKind = TFrameKind.Top)) then
  begin
    while S.Count > 1 do
      Pop;
    Place(0);
    if AWord = 'implementation' then
      S.InImplementation := True;
    S.AtStart := True;
    Exit;
  end;
  if MatchStr(AWord, ['unit', 'program', 'library', 'package']) and S.AtStart and (S.Count = 1) then
  begin
    Place(0);
    if AWord <> 'unit' then
      S.HasBodies := AWord <> 'package';
    StartStatement;
    Exit;
  end;
  // Abschnitte: uses, type, const, var usw. (in Anweisungen sind var und const Inline-Deklarationen).
  if (MatchStr(AWord, SectionWords) or ((AWord = 'requires') and (DeclKind = TFrameKind.Top))) and
    not InStatements and (DeclKind in [TFrameKind.Top, TFrameKind.Routine, TFrameKind.ClassBody]) and
    (S.AtStart or ((DeclKind = TFrameKind.Routine) and S.Frames[DeclIndex].Anonymous)) then
  begin
    PopSections;
    Frame := TopFrame;
    case Frame.Kind of
      TFrameKind.Top:
        Column := 0;
      TFrameKind.Routine:
        Column := Frame.Column;
    else
      Column := Frame.Column + FStep;
    end;
    if FFirst then
      Place(Column)
    else
      Column := LineColumn;
    Push(TFrameKind.Section, Column);
    S.AtStart := True;
    S.ClassPrefix := False;
    Exit;
  end;
  if MatchStr(AWord, VisibilityWords) and S.AtStart and (DeclKind = TFrameKind.ClassBody) then
  begin
    PopSections;
    Place(TopFrame.Column);
    S.AtStart := True;
    Exit;
  end;
  if MatchStr(AWord, RoutineWords) and ((AWord <> 'operator') or S.ClassPrefix) then
  begin
    if InStatements then
    begin
      // Anonyme Methode.
      PlaceStatement;
      StartStatement;
      if FFirst then
        Column := LineColumn
      else
        Column := LineColumn + FStep;
      Push(TFrameKind.Routine, Column);
      S.Frames[S.Count - 1].Anonymous := True;
      S.Frames[S.Count - 1].OuterStmtLine := S.StmtLine;
      S.Frames[S.Count - 1].OuterPendingCase := S.PendingCase;
      S.Frames[S.Count - 1].OuterCaseColumn := S.CaseColumn;
      S.PendingCase := False;
      Exit;
    end;
    if S.AtStart or S.ClassPrefix then
    begin
      if not S.ClassPrefix then
      begin
        PopSections;
        Frame := TopFrame;
        case Frame.Kind of
          TFrameKind.Top:
            Column := 0;
          TFrameKind.Routine:
            Column := Frame.Column + FStep;
        else
          Column := Frame.Column + FStep;
        end;
        Place(Column);
        S.StmtLine := FLine;
        S.AtStart := False;
      end
      else
        Column := FResolved[S.StmtLine];
      S.AfterHeader := True;
      S.ClassPrefix := False;
      Frame := TopFrame;
      if ((Frame.Kind = TFrameKind.Top) and (S.InImplementation or S.HasBodies)) or
        ((Frame.Kind = TFrameKind.Routine) and not Frame.HasBody) then
      begin
        S.PendingRoutine := True;
        S.RoutineColumn := Column;
      end;
      Exit;
    end;
  end;
  if (AWord = 'class') and S.AtStart and not InStatements then
  begin
    Previous := WordOf(NextSignificant(FIndex));
    if MatchStr(Previous, RoutineWords) or MatchStr(Previous, ['var', 'property', 'threadvar']) then
    begin
      if MatchStr(Previous, RoutineWords) then
        PopSections;
      PlaceStatement;
      StartStatement;
      S.ClassPrefix := MatchStr(Previous, RoutineWords) or (Previous = 'operator');
      S.AfterHeader := True;
      Exit;
    end;
  end;
  if S.AtStart and S.AfterHeader and MatchStr(AWord, DirectiveWords) and not InStatements then
  begin
    // Direktiven setzen den Kopf fort: Abstand zu dessen erster Zeile.
    if MatchStr(AWord, ['forward', 'external']) and (TopKind = TFrameKind.Routine) and not TopFrame.HasBody and
      not TopFrame.Anonymous then
      S.Frames[S.Count - 1].NoBody := True;
    S.AtStart := False;
    PlaceStatement;
    Exit;
  end;
  // Rümpfe von Klassen, Records und Interfaces.
  if MatchStr(AWord, ['class', 'record', 'object', 'interface', 'dispinterface']) then
  begin
    Index := FIndex - 1;
    while (Index >= 0) and (FTokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
      Dec(Index);
    Previous := WordOf(Index);
    if Previous = 'packed' then
    begin
      Dec(Index);
      while (Index >= 0) and (FTokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
        Dec(Index);
      Previous := WordOf(Index);
    end;
    if ((Previous = '=') or ((Previous = ':') and (AWord = 'record'))) and
      TypeHeaderEnd(FIndex, AWord, HeaderEnd) then
    begin
      PlaceStatement;
      StartStatement;
      if S.StmtLine >= 0 then
        Push(TFrameKind.ClassBody, FResolved[S.StmtLine])
      else
        Push(TFrameKind.ClassBody, LineColumn);
      S.HeaderEnd := HeaderEnd;
      Exit;
    end;
  end;
  if (AWord = 'case') and not S.PendingCase then
  begin
    PlaceStatement;
    StartStatement;
    S.PendingCase := True;
    S.CaseColumn := FResolved[S.StmtLine];
    Exit;
  end;
  if (AWord = 'of') and S.PendingCase and (S.Depth = TopFrame.Depth) then
  begin
    PlaceStatement;
    S.PendingCase := False;
    Push(TFrameKind.CaseBlock, S.CaseColumn);
    if DeclKind = TFrameKind.ClassBody then
      S.Frames[S.Count - 1].Variant := True;
    S.AtStart := True;
    Exit;
  end;
  if AWord = 'then' then
  begin
    PlaceStatement;
    Push(TFrameKind.IfPending, FResolved[Max(S.StmtLine, 0)]);
    S.AtStart := True;
    Exit;
  end;
  if AWord = 'do' then
  begin
    PlaceStatement;
    Push(TFrameKind.DoPending, FResolved[Max(S.StmtLine, 0)]);
    S.AtStart := True;
    Exit;
  end;
  PlaceStatement;
  StartStatement;
  if AWord = 'property' then
    S.AfterHeader := True;
end;

procedure TIndenter.Symbol(const AText: string);
var
  Base: Integer;
begin
  Base := TopFrame.Depth;
  if (AText = '(') or (AText = '[') then
  begin
    if S.AtStart and (AText = '[') and not InStatements then
      S.Attribute := True;
    PlaceStatement;
    StartStatement;
    Inc(S.Depth);
    Exit;
  end;
  if (AText = ')') or (AText = ']') then
  begin
    PlaceStatement;
    if S.Depth > 0 then
      Dec(S.Depth);
    if S.Attribute and (AText = ']') and (S.Depth = Base) then
    begin
      S.Attribute := False;
      S.AtStart := True;
    end;
    Exit;
  end;
  PlaceStatement;
  if (AText = ';') and (S.Depth <= Base) then
  begin
    S.Depth := Base;
    S.Attribute := False;
    S.PendingCase := False;
    if S.PendingRoutine then
    begin
      S.PendingRoutine := False;
      PopSections;
      Push(TFrameKind.Routine, S.RoutineColumn);
    end
    else if (TopKind = TFrameKind.Routine) and TopFrame.NoBody then
      Pop
    else
      PopPending;
    S.AtStart := True;
    Exit;
  end;
  if (AText = ':') and (TopKind = TFrameKind.CaseBlock) and TopFrame.InLabel and (S.Depth = Base) then
  begin
    S.Frames[S.Count - 1].InLabel := False;
    Push(TFrameKind.LabelPending, FResolved[Max(S.StmtLine, 0)]);
    S.AtStart := True;
    Exit;
  end;
  StartStatement;
end;

function TIndenter.Run(const ATokens: TArray<TPascalToken>; const AColumns: TArray<Integer>;
  AIndentSize: Integer): TArray<Integer>;
var
  Index, Line, Next, Delta: Integer;
  Token: TPascalToken;
  InAsm: Boolean;
begin
  FTokens := ATokens;
  FOriginal := AColumns;
  FStep := Max(AIndentSize, 1);
  SetLength(FResult, Length(AColumns));
  SetLength(FResolved, Length(AColumns));
  SetLength(FPlaced, Length(AColumns));
  SetLength(FFollow, Length(AColumns));
  SetLength(FFirstToken, Length(AColumns));
  for Line := 0 to High(AColumns) do
  begin
    FResult[Line] := TBlockIndenter.Keep;
    FResolved[Line] := AColumns[Line];
    FFirstToken[Line] := -1;
  end;
  for Index := 0 to High(ATokens) do
  begin
    Line := ATokens[Index].StartPos.Line;
    if (Line <= High(FFirstToken)) and (FFirstToken[Line] < 0) then
      FFirstToken[Line] := Index;
  end;
  S := Default(TIndentState);
  S.StmtLine := -1;
  S.HeaderEnd := -1;
  S.AtStart := True;
  Push(TFrameKind.Top, 0);
  FBranches := nil;
  FAlternatives := 0;
  for Index := 0 to High(ATokens) do
  begin
    Token := ATokens[Index];
    FIndex := Index;
    FLine := Token.StartPos.Line;
    if FLine > High(FFirstToken) then
      Break;
    FFirst := (FFirstToken[FLine] = Index) and (FAlternatives = 0);
    InAsm := TopKind = TFrameKind.AsmBlock;
    if Token.Kind = TPascalTokenKind.Directive then
    begin
      Directive(Token);
      Continue;
    end;
    if Token.Kind = TPascalTokenKind.Comment then
    begin
      if FFirst and not InAsm then
        FFollow[FLine] := True;
      Continue;
    end;
    if InAsm then
    begin
      if (Token.Kind = TPascalTokenKind.Keyword) and Token.IsKeyword('end') then
        CloseEnd;
      Continue;
    end;
    if Token.Kind in [TPascalTokenKind.Keyword, TPascalTokenKind.Identifier] then
      Word(LowerCase(Token.Text))
    else if Token.Kind = TPascalTokenKind.Symbol then
      Symbol(Token.Text)
    else
    begin
      PlaceStatement;
      StartStatement;
    end;
    if Index = S.HeaderEnd then
    begin
      S.HeaderEnd := -1;
      S.AtStart := True;
    end;
  end;
  // Kommentarzeilen folgen der nächsten Codezeile.
  for Line := High(FFollow) downto 0 do
    if FFollow[Line] and not FPlaced[Line] then
    begin
      Next := Line + 1;
      while (Next <= High(FFollow)) and not FPlaced[Next] and (FFirstToken[Next] < 0) do
        Inc(Next);
      Delta := 0;
      if (Next <= High(FFollow)) and FPlaced[Next] then
        Delta := FResolved[Next] - FOriginal[Next];
      if Delta <> 0 then
      begin
        FResult[Line] := Max(FOriginal[Line] + Delta, 0);
        FResolved[Line] := FResult[Line];
        FPlaced[Line] := True;
      end;
    end;
  Result := FResult;
end;

{ TBlockIndenter }

class function TBlockIndenter.Columns(const ATokens: TArray<TPascalToken>; const AColumns: TArray<Integer>;
  AIndentSize: Integer): TArray<Integer>;
var
  Indenter: TIndenter;
begin
  Indenter := TIndenter.Create;
  try
    Result := Indenter.Run(ATokens, AColumns, AIndentSize);
  finally
    Indenter.Free;
  end;
end;

end.
