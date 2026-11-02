unit Atlas.Common.Editing.WinApiCommands;

// Schnellbefehle für Windows-API und DLLs (#321) im Rahmen aus #293:
//   /external Name dll [delayed] [cdecl]  Importdeklaration; DLL-Name als Konstante,
//                                         wenn die Unit schon mehrere Importe daraus hat
//   /exports [Name]                       Routinen der library in die exports-Klausel
//   /oscheck                              Win32Check(…) bzw. "if … = 0 then RaiseLastOSError"
//   /olecheck                             OleCheck(…) um den COM-Aufruf darunter
// Der Rückgabetyp kommt aus der Unit, dem Symbolindex bzw. einer Liste
// bekannter API-Funktionen.

interface

uses
  Atlas.Common.Editing.Contract;

/// <summary>Trägt /external, /exports, /oscheck und /olecheck über ARegister ein.</summary>
procedure RegisterWinApiCommands(const ARegister: TSlashRegister);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.CommandSource;

type
  TTokens = TArray<TPascalToken>;

const
  Conventions: array[0..5] of string = ('stdcall', 'cdecl', 'register', 'pascal', 'safecall', 'winapi');
  // Häufige Funktionen aus Winapi.Windows mit BOOL-Ergebnis, falls der Index sie nicht kennt.
  BoolFunctions: array[0..33] of string = ('CloseHandle', 'DeleteFile', 'CopyFile', 'MoveFile', 'MoveFileEx',
    'ReadFile', 'WriteFile', 'CreateDirectory', 'RemoveDirectory', 'SetEvent', 'ResetEvent', 'ReleaseMutex',
    'FreeLibrary', 'SetWindowPos', 'PostMessage', 'PostThreadMessage', 'DestroyWindow', 'SetCurrentDirectory',
    'GetExitCodeProcess', 'TerminateProcess', 'DuplicateHandle', 'FlushFileBuffers', 'SetEndOfFile', 'LockFile',
    'UnlockFile', 'GetFileTime', 'SetFileTime', 'GetComputerName', 'GetUserName', 'SystemParametersInfo',
    'SetFileAttributes', 'CreateProcess', 'ReleaseSemaphore', 'SetThreadPriority');
  BoolTypes: array[0..3] of string = ('BOOL', 'LongBool', 'Boolean', 'WordBool');

function IsCode(const AToken: TPascalToken): Boolean;
begin
  Result := not (AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

{ /external }

/// <summary>Bezeichner aus dem DLL-Namen: meine.dll wird zu MeineDll.</summary>
function DllConstName(const ADll: string): string;
var
  C: Char;
  Upper: Boolean;
begin
  Result := '';
  Upper := True;
  for C in ChangeFileExt(ExtractFileName(ADll), '') do
  begin
    if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9']) then
    begin
      if Upper then
      begin
        Result := Result + UpperCase(C);
      end
      else
      begin
        Result := Result + C;
      end;
      Upper := False;
    end
    else
    begin
      Upper := True;
    end;
  end;
  if (Result = '') or CharInSet(Result[1], ['0'..'9']) then
  begin
    Result := 'Lib' + Result;
  end;
  Result := Result + 'Dll';
end;

function ExecuteExternal(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Words: TArray<string>;
  Name, Dll, Convention, Suffix, Library_, Declaration, Indent, ConstName, LB: string;
  Tokens: TTokens;
  Index, Next, Count: Integer;
  ClassSymbol: TIndexSymbol;
  Constant: TIndexSymbol;
  Delayed: Boolean;
begin
  AEdits := nil;
  Declaration := '';
  Words := AContext.Arguments.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  if (Length(Words) < 2) or not IsValidIdent(Words[0]) then
  begin
    Exit(Fail('Erwartet wird /external Name dll [delayed] [cdecl]', AReason));
  end;
  Name := Words[0];
  Dll := Words[1];
  if (Length(Dll) >= 2) and (Dll[1] = '''') and (Dll[Length(Dll)] = '''') then
  begin
    Dll := Copy(Dll, 2, Length(Dll) - 2);
  end;
  Convention := 'stdcall';
  Delayed := False;
  for Index := 2 to High(Words) do
  begin
    if SameText(Words[Index], 'delayed') then
    begin
      Delayed := True;
    end
    else if MatchText(Words[Index], Conventions) then
    begin
      Convention := LowerCase(Words[Index]);
    end
    else
    begin
      Exit(Fail(Format('Unbekannte Angabe %s; erlaubt sind delayed und %s', [Words[Index],
        string.Join(', ', Conventions)]), AReason));
    end;
  end;
  Source := TCommandSource.Create(AContext);
  try
    if (Source.RoutineAt = nil) and Source.ClassAt(ClassSymbol) then
    begin
      Exit(Fail('/external gehört nicht in eine Klasse', AReason));
    end;
    LB := Source.LineBreak;
    // Importe aus derselben DLL zählen; ab zwei vorhandenen kommt der Name in eine Konstante.
    Tokens := Source.Tree.Tokens;
    Count := 0;
    for Index := 0 to High(Tokens) - 1 do
    begin
      if SameText(Tokens[Index].Text, 'external') then
      begin
        Next := Index + 1;
        while (Next <= High(Tokens)) and not IsCode(Tokens[Next]) do
        begin
          Inc(Next);
        end;
        if (Next <= High(Tokens)) and SameText(Tokens[Next].Text, QuotedStr(Dll)) then
        begin
          Inc(Count);
        end;
      end;
    end;
    Library_ := QuotedStr(Dll);
    ConstName := '';
    if Count >= 2 then
    begin
      for Constant in Source.UnitIndex.Symbols do
      begin
        if (Constant.Kind = TIndexSymbolKind.Constant) and (Constant.Container = '') and
          ContainsText(Source.Lines[Constant.Range.StartPos.Line], QuotedStr(Dll)) then
        begin
          ConstName := Constant.Name;
        end;
      end;
      if ConstName = '' then
      begin
        ConstName := DllConstName(Dll);
        Declaration := 'const' + LB + Format('  %s = %s;', [ConstName, QuotedStr(Dll)]) + LB + LB;
      end;
      Library_ := ConstName;
    end;
    Suffix := '';
    if Delayed then
    begin
      Suffix := ' delayed';
    end;
    // Parameterliste und Ergebnis ergänzt der Entwickler; "()" hält die Deklaration übersetzbar.
    if (ConstName <> '') and (Declaration <> '') then
    begin
      Declaration := Declaration + Format('procedure %s(); %s; external %s%s;', [Name, Convention, Library_, Suffix]);
    end
    else
    begin
      Declaration := Format('procedure %s(); %s; external %s%s;', [Name, Convention, Library_, Suffix]);
    end;
    if Source.RoutineAt <> nil then
    begin
      // Aus einer Routine heraus: in die implementation wie /const!.
      if Source.ImplementationStart < 0 then
      begin
        Exit(Fail('/external braucht hier einen implementation-Abschnitt', AReason));
      end;
      AEdits := [Source.AfterLine(Source.ImplementationStart, LB + Declaration), Source.RemoveCommand];
    end
    else
    begin
      Indent := Source.Indent(Source.Line);
      AEdits := [TTextEdit.Create(TTextRange.Create(Source.Line, 0, Source.Line + 1, 0),
        Indent + StringReplace(Declaration, LB, LB + Indent, [rfReplaceAll]) + LB)];
    end;
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /exports }

function HasConvention(ARoutine: TSyntaxNode): Boolean;
var
  Header: TSyntaxNode;
  Index: Integer;
begin
  Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if Header = nil then
  begin
    Header := ARoutine;
  end;
  for Index := 0 to Header.ChildCount - 1 do
  begin
    if (Header[Index].Kind = TSyntaxKind.Directive) and MatchText(Header[Index].Name, Conventions) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function ExecuteExports(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Root, Clause, Main: TSyntaxNode;
  Names, Missing, Listed: TArray<string>;
  Index: Integer;
  Token: TPascalToken;
  Name, LB, Text: string;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    Root := Source.Tree.Root;
    if (Root = nil) or (Root.Kind <> TSyntaxKind.LibraryFile) then
    begin
      Exit(Fail('/exports gilt nur in einer library-Datei (.dpr)', AReason));
    end;
    Clause := Root.FindChild(TSyntaxKind.ExportsClause);
    Main := Root.FindChild(TSyntaxKind.Block);
    Listed := nil;
    if Clause <> nil then
    begin
      for Token in Source.Tree.Tokens do
      begin
        if (Token.Kind = TPascalTokenKind.Identifier) and (Token.StartPos.Line >= Clause.StartPos.Line) and
          (Token.EndPos.Line <= Clause.EndPos.Line) then
        begin
          Listed := Listed + [Token.Text];
        end;
      end;
    end;
    Names := nil;
    Missing := nil;
    for Index := 0 to Root.ChildCount - 1 do
    begin
      if (Root[Index].Kind = TSyntaxKind.RoutineDecl) and (Pos('.', Root[Index].Name) = 0) and
        ((AContext.Arguments = '') or SameText(Root[Index].Name, AContext.Arguments)) and
        (IndexText(Root[Index].Name, Listed) < 0) then
      begin
        if HasConvention(Root[Index]) then
        begin
          Names := Names + [Root[Index].Name];
        end
        else
        begin
          Missing := Missing + [Root[Index].Name];
        end;
      end;
    end;
    if Names = nil then
    begin
      if Missing <> nil then
      begin
        Exit(Fail('Ohne Aufrufkonvention (stdcall, cdecl): ' + string.Join(', ', Missing), AReason));
      end;
      if AContext.Arguments <> '' then
      begin
        Exit(Fail(Format('Keine Routine %s, die noch nicht exportiert wird', [AContext.Arguments]), AReason));
      end;
      Exit(Fail('Alle Routinen stehen schon in exports', AReason));
    end;
    LB := Source.LineBreak;
    Text := '';
    for Name in Names do
    begin
      Text := Text + ',' + LB + '  ' + Name;
    end;
    if Clause <> nil then
    begin
      // Vor dem abschließenden ";" der Klausel anhängen.
      for Token in Source.Tree.Tokens do
      begin
        if Token.IsSymbol(';') and (Token.EndPos.Line = Clause.EndPos.Line) and
          (Token.EndPos.Character = Clause.EndPos.Character) then
        begin
          AEdits := [TTextEdit.Create(TTextRange.Create(Token.StartPos, Token.StartPos), Text)];
        end;
      end;
      if AEdits = nil then
      begin
        Exit(Fail('exports-Klausel ohne abschließendes ";"', AReason));
      end;
    end
    else
    begin
      if Main = nil then
      begin
        Exit(Fail('Hauptblock der library nicht gefunden', AReason));
      end;
      AEdits := [Source.BeforeLine(Main.StartPos.Line, 'exports' + Copy(Text, 2, MaxInt) + ';')];
    end;
    AEdits := AEdits + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /oscheck und /olecheck }

type
  TStatement = record
    /// <summary>Vom ersten Token bis vor das ";".</summary>
    Range: TTextRange;
    Text: string;
    /// <summary>Linke Seite bei einer Zuweisung, sonst ''.</summary>
    Target: string;
    /// <summary>Aufgerufene Routine (letzter Name vor der Klammer).</summary>
    Callee: string;
  end;

/// <summary>Anweisung unter der Befehlszeile; False ohne Aufruf.</summary>
function StatementBelow(ASource: TCommandSource; out AStatement: TStatement): Boolean;
var
  Tokens: TTokens;
  First, Index, Depth, Assign, Open: Integer;
begin
  Result := False;
  Tokens := ASource.Tree.Tokens;
  First := -1;
  for Index := 0 to High(Tokens) do
  begin
    if (Tokens[Index].StartPos.Line > ASource.Line) and IsCode(Tokens[Index]) then
    begin
      First := Index;
      Break;
    end;
  end;
  if (First < 0) or (Tokens[First].Kind <> TPascalTokenKind.Identifier) then
  begin
    Exit;
  end;
  Depth := 0;
  Assign := -1;
  Open := -1;
  Index := First;
  while Index <= High(Tokens) do
  begin
    if Tokens[Index].IsSymbol('(') or Tokens[Index].IsSymbol('[') then
    begin
      if (Depth = 0) and (Open < 0) and Tokens[Index].IsSymbol('(') then
      begin
        Open := Index;
      end;
      Inc(Depth);
    end
    else if Tokens[Index].IsSymbol(')') or Tokens[Index].IsSymbol(']') then
    begin
      Dec(Depth);
    end
    else if (Depth = 0) and Tokens[Index].IsSymbol(':=') then
    begin
      Assign := Index;
    end
    else if (Depth = 0) and (Tokens[Index].IsSymbol(';') or Tokens[Index].IsKeyword('end') or
      Tokens[Index].IsKeyword('else') or Tokens[Index].IsKeyword('until') or Tokens[Index].IsKeyword('begin')) then
    begin
      Break;
    end;
    Inc(Index);
  end;
  if (Index > High(Tokens)) or not Tokens[Index].IsSymbol(';') or (Open <= First) or (Open < Assign) then
  begin
    Exit;
  end;
  AStatement.Range := TTextRange.Create(Tokens[First].StartPos, Tokens[Index].StartPos);
  AStatement.Text := '';
  for Depth := First to Index - 1 do
  begin
    if (Depth > First) and ((Tokens[Depth].StartPos.Line <> Tokens[Depth - 1].EndPos.Line) or
      (Tokens[Depth].StartPos.Character <> Tokens[Depth - 1].EndPos.Character)) then
    begin
      AStatement.Text := AStatement.Text + ' ';
    end;
    AStatement.Text := AStatement.Text + Tokens[Depth].Text;
  end;
  AStatement.Target := '';
  if Assign >= 0 then
  begin
    for Depth := First to Assign - 1 do
    begin
      AStatement.Target := AStatement.Target + Tokens[Depth].Text;
    end;
  end;
  AStatement.Callee := Tokens[Open - 1].Text;
  Result := Tokens[Open - 1].Kind = TPascalTokenKind.Identifier;
end;

/// <summary>Rückgabetyp von AName aus Unit bzw. Index; '' wenn unbekannt.</summary>
function ResultType(ASource: TCommandSource; const AIndex: ISymbolIndex; const AName: string): string;
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
begin
  for Symbol in ASource.UnitIndex.Symbols do
  begin
    if (Symbol.Kind in [TIndexSymbolKind.Routine, TIndexSymbolKind.Method]) and SameText(Symbol.Name, AName) then
    begin
      Exit(IfThen(Symbol.TypeName = '', '-', Symbol.TypeName));
    end;
  end;
  if AIndex <> nil then
  begin
    for Location in AIndex.FindSymbols(AName) do
    begin
      if Location.Symbol.Kind in [TIndexSymbolKind.Routine, TIndexSymbolKind.Method] then
      begin
        Exit(IfThen(Location.Symbol.TypeName = '', '-', Location.Symbol.TypeName));
      end;
    end;
  end;
  if MatchText(AName, BoolFunctions) or MatchText(Copy(AName, 1, Length(AName) - 1), BoolFunctions) and
    CharInSet(AName[Length(AName)], ['A', 'W']) then
  begin
    Exit('BOOL');
  end;
  Result := '';
end;

/// <summary>Ersetzt Befehlszeile und Anweisung bzw. ergänzt danach eine Zeile.</summary>
function WrapStatement(ASource: TCommandSource; const AStatement: TStatement;
  const ANewText: string): TArray<TTextEdit>;
begin
  if AStatement.Range.StartPos.Line = ASource.Line + 1 then
  begin
    Result := [TTextEdit.Create(TTextRange.Create(TTextPosition.Create(ASource.Line, 0), AStatement.Range.EndPos),
      Copy(ASource.Lines[ASource.Line + 1], 1, AStatement.Range.StartPos.Character) + ANewText)];
  end
  else
  begin
    Result := [TTextEdit.Create(AStatement.Range, ANewText), ASource.RemoveCommand];
  end;
end;

function ExecuteOsCheck(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Statement: TStatement;
  TypeName, Condition, Indent: string;
  Line: Integer;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if Source.RoutineAt = nil then
    begin
      Exit(Fail('/oscheck gilt nur im Rumpf einer Routine', AReason));
    end;
    if not StatementBelow(Source, Statement) then
    begin
      Exit(Fail('Unter /oscheck steht kein Aufruf', AReason));
    end;
    TypeName := ResultType(Source, AContext.Index, Statement.Callee);
    if Statement.Target = '' then
    begin
      if TypeName = '' then
      begin
        Exit(Fail(Format('Rückgabetyp von %s unbekannt; Win32Check nur bei BOOL', [Statement.Callee]), AReason));
      end;
      if not MatchText(TypeName, BoolTypes) then
      begin
        Exit(Fail(Format('%s liefert %s, nicht BOOL; Win32Check passt nicht', [Statement.Callee,
          IfThen(TypeName = '-', 'nichts', TypeName)]), AReason));
      end;
      AEdits := WrapStatement(Source, Statement, 'Win32Check(' + Statement.Text + ')');
    end
    else
    begin
      // Rückgabewert genutzt: danach prüfen.
      if MatchText(TypeName, BoolTypes) then
      begin
        Condition := Format('not %s', [Statement.Target]);
      end
      else
      begin
        Condition := Format('%s = 0', [Statement.Target]);
      end;
      Line := Statement.Range.EndPos.Line;
      Indent := Source.Indent(Statement.Range.StartPos.Line);
      AEdits := [Source.AfterLine(Line, Format('%sif %s then', [Indent, Condition]) + Source.LineBreak + Indent +
        '  RaiseLastOSError;'), Source.RemoveCommand];
    end;
    AddUses(Source, AContext, Source.Line, ['System.SysUtils'], AEdits);
    Result := True;
  finally
    Source.Free;
  end;
end;

function ExecuteOleCheck(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  Statement: TStatement;
  TypeName, Indent: string;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if Source.RoutineAt = nil then
    begin
      Exit(Fail('/olecheck gilt nur im Rumpf einer Routine', AReason));
    end;
    if not StatementBelow(Source, Statement) then
    begin
      Exit(Fail('Unter /olecheck steht kein Aufruf', AReason));
    end;
    TypeName := ResultType(Source, AContext.Index, Statement.Callee);
    if (TypeName <> '') and not MatchText(TypeName, ['HRESULT', 'HResult']) then
    begin
      Exit(Fail(Format('%s liefert %s, nicht HRESULT', [Statement.Callee, IfThen(TypeName = '-', 'nichts',
        TypeName)]), AReason));
    end;
    if Statement.Target = '' then
    begin
      AEdits := WrapStatement(Source, Statement, 'OleCheck(' + Statement.Text + ')');
    end
    else
    begin
      Indent := Source.Indent(Statement.Range.StartPos.Line);
      AEdits := [Source.AfterLine(Statement.Range.EndPos.Line, Format('%sOleCheck(%s);', [Indent,
        Statement.Target])), Source.RemoveCommand];
    end;
    AddUses(Source, AContext, Source.Line, ['System.Win.ComObj'], AEdits);
    Result := True;
  finally
    Source.Free;
  end;
end;

function Command(const AName, ASummary, AExample: string; const AExecute: TSlashExecute): TSlashCommand;
begin
  Result.Name := AName;
  Result.Summary := ASummary;
  Result.Example := AExample;
  Result.Execute := AExecute;
end;

procedure RegisterWinApiCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('external', 'Funktion aus einer DLL importieren', '/external MeineFunktion meine.dll',
    ExecuteExternal));
  ARegister(Command('exports', 'Routinen der library exportieren', '/exports', ExecuteExports));
  ARegister(Command('oscheck', 'Windows-API-Aufruf darunter prüfen', '/oscheck', ExecuteOsCheck));
  ARegister(Command('olecheck', 'COM-Aufruf darunter mit OleCheck prüfen', '/olecheck', ExecuteOleCheck));
end;

end.
