unit Atlas.Common.Editing.ClassCommands;

// Schnellbefehle für Klassen (#295) im Rahmen aus #293:
//   /impl            fehlende Methodenrümpfe der Klasse anlegen
//   /ctor [owner]    Konstruktor mit den Feldern als Parametern; "owner" für Komponenten;
//                    "/ctor FName, FAlter" nur mit diesen Feldern (Auswahl im Erzeugen-Menü, #719)
//   /dtor            Destruktor, der im Konstruktor erzeugte Felder freigibt; einen vorhandenen
//                    ergänzt er um die noch nicht freigegebenen
//   /override Name   virtuelle Methode eines Vorfahren überschreiben (auch aus dem Index)
//   /msg WM_SIZE     Botschaftsmethode mit passendem Record
//   /intf IFoo       IFoo an die Klasse hängen, Deklarationen und Rümpfe aller fehlenden
//                    Interface-Methoden anlegen (derselbe Erzeuger wie die Vervollständigung, #466)
//
// Deklarationen kommen in einen eigenen Abschnitt vor "end" der Klasse, Rümpfe
// hinter die letzte Methode der Klasse. Für die Auswahl im Erzeugen-Menü (#719)
// liefern CtorFields, OverrideCandidates und MessageNames die möglichen
// Argumente.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.Contract;

/// <summary>Trägt die Klassenbefehle über ARegister ein.</summary>
procedure RegisterClassCommands(const ARegister: TSlashRegister);

/// <summary>Methodenname zur Botschaft: WM_SIZE wird zu WMSize, CM_MOUSEENTER zu CMMouseEnter (Tabelle, sonst je Teil groß).</summary>
function MessageMethodName(const AMessage: string): string;
/// <summary>Record-Typ zur Botschaft, TMessage ohne Eintrag in der Tabelle.</summary>
function MessageRecord(const AMessage: string): string;
/// <summary>Kopf "procedure Name(...)" bzw. "function Name(...): Typ" ohne Direktiven.</summary>
function RoutineSignature(const ADeclaration: string): string;
/// <summary>Parameternamen aus dem Kopf, kommagetrennt.</summary>
function ParameterNames(const ASignature: string): string;
/// <summary>Text in ARange aus ALines, Zeilen mit Leerzeichen verbunden.</summary>
function RangeText(const ALines: TArray<string>; const ARange: TTextRange): string;
function LoadText(const AFileName: string; out AText: string): Boolean;
/// <summary>Felder der Klasse um die Befehlszeile, die /ctor als Parameter nimmt (#719); leer außerhalb.</summary>
function CtorFields(const AContext: TSlashContext): TArray<string>;
/// <summary>Virtuelle Methoden der Vorfahren (Datei, dann Index), die die Klasse um die Befehlszeile noch nicht
/// selbst deklariert; Namen in der Reihenfolge der Vorfahren, ohne Doppelte (#719).</summary>
function OverrideCandidates(const AContext: TSlashContext): TArray<string>;
/// <summary>Botschaften der Tabelle, z. B. WM_SIZE (#719).</summary>
function MessageNames: TArray<string>;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Classes,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassCompletion,
  Atlas.Common.Editing.ClassMembers,
  Atlas.Common.Editing.CommandSource;

type
  TMessageEntry = record
    Name: string;
    Method: string;
    RecordType: string;
  end;

const
  // Häufige Botschaften mit Methodennamen wie in der VCL und Record aus Winapi.Messages bzw. Vcl.Controls.
  MessageTable: array[0..37] of TMessageEntry = (
    (Name: 'WM_SIZE'; Method: 'WMSize'; RecordType: 'TWMSize'),
    (Name: 'WM_MOVE'; Method: 'WMMove'; RecordType: 'TWMMove'),
    (Name: 'WM_PAINT'; Method: 'WMPaint'; RecordType: 'TWMPaint'),
    (Name: 'WM_ERASEBKGND'; Method: 'WMEraseBkgnd'; RecordType: 'TWMEraseBkgnd'),
    (Name: 'WM_KEYDOWN'; Method: 'WMKeyDown'; RecordType: 'TWMKeyDown'),
    (Name: 'WM_KEYUP'; Method: 'WMKeyUp'; RecordType: 'TWMKeyUp'),
    (Name: 'WM_CHAR'; Method: 'WMChar'; RecordType: 'TWMChar'),
    (Name: 'WM_LBUTTONDOWN'; Method: 'WMLButtonDown'; RecordType: 'TWMLButtonDown'),
    (Name: 'WM_LBUTTONUP'; Method: 'WMLButtonUp'; RecordType: 'TWMLButtonUp'),
    (Name: 'WM_MOUSEMOVE'; Method: 'WMMouseMove'; RecordType: 'TWMMouseMove'),
    (Name: 'WM_MOUSEWHEEL'; Method: 'WMMouseWheel'; RecordType: 'TWMMouseWheel'),
    (Name: 'WM_SETFOCUS'; Method: 'WMSetFocus'; RecordType: 'TWMSetFocus'),
    (Name: 'WM_KILLFOCUS'; Method: 'WMKillFocus'; RecordType: 'TWMKillFocus'),
    (Name: 'WM_TIMER'; Method: 'WMTimer'; RecordType: 'TWMTimer'),
    (Name: 'WM_COMMAND'; Method: 'WMCommand'; RecordType: 'TWMCommand'),
    (Name: 'WM_NOTIFY'; Method: 'WMNotify'; RecordType: 'TWMNotify'),
    (Name: 'WM_GETMINMAXINFO'; Method: 'WMGetMinMaxInfo'; RecordType: 'TWMGetMinMaxInfo'),
    (Name: 'WM_NCHITTEST'; Method: 'WMNCHitTest'; RecordType: 'TWMNCHitTest'),
    (Name: 'WM_DROPFILES'; Method: 'WMDropFiles'; RecordType: 'TWMDropFiles'),
    (Name: 'WM_CLOSE'; Method: 'WMClose'; RecordType: 'TWMClose'),
    (Name: 'WM_SYSCOMMAND'; Method: 'WMSysCommand'; RecordType: 'TWMSysCommand'),
    (Name: 'WM_CONTEXTMENU'; Method: 'WMContextMenu'; RecordType: 'TWMContextMenu'),
    (Name: 'WM_SETCURSOR'; Method: 'WMSetCursor'; RecordType: 'TWMSetCursor'),
    (Name: 'WM_SHOWWINDOW'; Method: 'WMShowWindow'; RecordType: 'TWMShowWindow'),
    (Name: 'CM_MOUSEENTER'; Method: 'CMMouseEnter'; RecordType: 'TMessage'),
    (Name: 'CM_MOUSELEAVE'; Method: 'CMMouseLeave'; RecordType: 'TMessage'),
    (Name: 'CM_FONTCHANGED'; Method: 'CMFontChanged'; RecordType: 'TMessage'),
    (Name: 'CM_COLORCHANGED'; Method: 'CMColorChanged'; RecordType: 'TMessage'),
    (Name: 'CM_ENABLEDCHANGED'; Method: 'CMEnabledChanged'; RecordType: 'TMessage'),
    (Name: 'CM_TEXTCHANGED'; Method: 'CMTextChanged'; RecordType: 'TMessage'),
    (Name: 'CM_VISIBLECHANGED'; Method: 'CMVisibleChanged'; RecordType: 'TMessage'),
    (Name: 'CM_DIALOGKEY'; Method: 'CMDialogKey'; RecordType: 'TCMDialogKey'),
    (Name: 'CM_DIALOGCHAR'; Method: 'CMDialogChar'; RecordType: 'TCMDialogChar'),
    (Name: 'CM_HINTSHOW'; Method: 'CMHintShow'; RecordType: 'TCMHintShow'),
    (Name: 'CM_STYLECHANGED'; Method: 'CMStyleChanged'; RecordType: 'TMessage'),
    (Name: 'CN_COMMAND'; Method: 'CNCommand'; RecordType: 'TWMCommand'),
    (Name: 'CN_NOTIFY'; Method: 'CNNotify'; RecordType: 'TWMNotify'),
    (Name: 'CN_KEYDOWN'; Method: 'CNKeyDown'; RecordType: 'TWMKeyDown'));

function MessageMethodName(const AMessage: string): string;
var
  Entry: TMessageEntry;
  Parts: TArray<string>;
  Index: Integer;
begin
  for Entry in MessageTable do
  begin
    if SameText(Entry.Name, Trim(AMessage)) then
    begin
      Exit(Entry.Method);
    end;
  end;
  // Unbekannte Botschaft: Präfix groß, jeder weitere Teil mit großem Anfangsbuchstaben.
  Parts := UpperCase(Trim(AMessage)).Split(['_']);
  if Length(Parts) = 0 then
  begin
    Exit('');
  end;
  Result := Parts[0];
  for Index := 1 to High(Parts) do
  begin
    if Parts[Index] <> '' then
    begin
      Result := Result + Parts[Index][1] + LowerCase(Copy(Parts[Index], 2, MaxInt));
    end;
  end;
end;

function MessageRecord(const AMessage: string): string;
var
  Entry: TMessageEntry;
begin
  for Entry in MessageTable do
  begin
    if SameText(Entry.Name, Trim(AMessage)) then
    begin
      Exit(Entry.RecordType);
    end;
  end;
  Result := 'TMessage';
end;

function RoutineSignature(const ADeclaration: string): string;
var
  Index, Depth: Integer;
  Text: string;
begin
  Text := StringReplace(StringReplace(ADeclaration, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  Depth := 0;
  for Index := 1 to Length(Text) do
    case Text[Index] of
      '(': Inc(Depth);
      ')': Dec(Depth);
      ';':
        if Depth = 0 then
        begin
          Text := Copy(Text, 1, Index - 1);
          Break;
        end;
    end;
  // Zeilenumbrüche und Einrückung zu einem Leerzeichen.
  while Pos('  ', Text) > 0 do
  begin
    Text := StringReplace(Text, '  ', ' ', [rfReplaceAll]);
  end;
  Result := Trim(Text);
end;

function ParameterNames(const ASignature: string): string;
var
  Open, Close, Colon: Integer;
  Group, Names: string;
  Name: string;
begin
  Result := '';
  Open := Pos('(', ASignature);
  Close := LastDelimiter(')', ASignature);
  if (Open = 0) or (Close < Open) then
  begin
    Exit;
  end;
  for Group in Copy(ASignature, Open + 1, Close - Open - 1).Split([';']) do
  begin
    Colon := Pos(':', Group);
    if Colon > 0 then
    begin
      Names := Copy(Group, 1, Colon - 1);
    end
    else
    begin
      Names := Group;
    end;
    Names := Trim(Names);
    // Modifizierer const, var, out, constref vor den Namen weglassen.
    if StartsText('const ', Names) or StartsText('var ', Names) or StartsText('out ', Names) or
      StartsText('constref ', Names) then
    begin
      Names := Trim(Copy(Names, Pos(' ', Names) + 1, MaxInt));
    end;
    for Name in Names.Split([',']) do
    begin
      if Trim(Name) <> '' then
      begin
        if Result <> '' then
        begin
          Result := Result + ', ';
        end;
        Result := Result + Trim(Name);
      end;
    end;
  end;
end;

/// <summary>Abschnitt mit Deklaration vor "end" der Klasse und Rumpf in der implementation.</summary>
function AddMethod(ASource: TCommandSource; const AClass: TIndexSymbol; const ASection, ADeclaration,
  ABody: string): TArray<TTextEdit>;
var
  EndLine: Integer;
  Indent: string;
begin
  EndLine := AClass.Range.EndPos.Line;
  Indent := ASource.Indent(EndLine);
  Result := [ASource.BeforeLine(EndLine, Indent + ASection + ASource.LineBreak + Indent + '  ' + ADeclaration),
    ASource.AddBody(AClass.Name, ABody), ASource.RemoveCommand];
end;

function Lines(ASource: TCommandSource; const AParts: array of string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(AParts) do
  begin
    if Index > 0 then
    begin
      Result := Result + ASource.LineBreak;
    end;
    Result := Result + AParts[Index];
  end;
end;

{ /impl }

function ExecuteImpl(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Action: TCodeAction;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
    begin
      Exit(Fail('/impl gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    end;
    if not TClassCompletion.MissingBodies(Source.Tree, Source.Text,
      TTextPosition.Create(ClassSymbol.SelectionRange.StartPos.Line, 0), Action) then
    begin
      Exit(Fail('Alle Methoden von ' + ClassSymbol.Name + ' haben einen Rumpf', AReason));
    end;
    AEdits := Action.Edits + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /ctor }

function ExecuteCtor(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol, Symbol: TIndexSymbol;
  Parameters, Assignments, Declaration, Body, Parameter, Name: string;
  Chosen: TArray<string>;
  Found: Boolean;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
    begin
      Exit(Fail('/ctor gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    end;
    if SameText(AContext.Arguments, 'owner') then
    begin
      Declaration := 'constructor Create(AOwner: TComponent); override;';
      Body := Lines(Source, [Format('constructor %s.Create(AOwner: TComponent);', [ClassSymbol.Name]), 'begin',
        '  inherited Create(AOwner);', 'end;']);
    end
    else
    begin
      // Ohne Argument alle Felder, sonst nur die genannten (mit oder ohne F).
      Chosen := nil;
      for Name in AContext.Arguments.Split([',', ' ', ';']) do
      begin
        if Name = '' then
        begin
          Continue;
        end;
        Found := False;
        for Symbol in Source.UnitIndex.Symbols do
        begin
          if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, ClassSymbol.Name) and
            (Symbol.TypeName <> '') and (SameText(Symbol.Name, Name) or SameText(Symbol.Name, 'F' + Name)) then
          begin
            Chosen := Chosen + [Symbol.Name];
            Found := True;
          end;
        end;
        if not Found then
        begin
          Exit(Fail(Format('Erwartet wird /ctor, /ctor owner oder /ctor FeldA, FeldB; kein Feld %s in %s',
            [Name, ClassSymbol.Name]), AReason));
        end;
      end;
      Parameters := '';
      Assignments := '';
      for Symbol in Source.UnitIndex.Symbols do
      begin
        if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, ClassSymbol.Name) and
          (Symbol.TypeName <> '') and ((Chosen = nil) or MatchText(Symbol.Name, Chosen)) then
        begin
          Parameter := 'A' + IfThen(StartsText('F', Symbol.Name) and (Length(Symbol.Name) > 1),
            Copy(Symbol.Name, 2, MaxInt), Symbol.Name);
          if Parameters <> '' then
          begin
            Parameters := Parameters + '; ';
          end;
          Parameters := Parameters + Format('const %s: %s', [Parameter, Symbol.TypeName]);
          Assignments := Assignments + Source.LineBreak + Format('  %s := %s;', [Symbol.Name, Parameter]);
        end;
      end;
      if Parameters <> '' then
      begin
        Parameters := '(' + Parameters + ')';
      end;
      Declaration := Format('constructor Create%s;', [Parameters]);
      Body := Format('constructor %s.Create%s;', [ClassSymbol.Name, Parameters]) + Source.LineBreak + 'begin' +
        Source.LineBreak + '  inherited Create;' + Assignments + Source.LineBreak + 'end;';
    end;
    AEdits := AddMethod(Source, ClassSymbol, 'public', Declaration, Body);
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /dtor }

/// <summary>Freigabe von AField in der Zeile: FreeAndNil(F), F.Free oder F.DisposeOf.</summary>
function FreesField(const ALine, AField: string): Boolean;
var
  Line: string;
begin
  Line := LowerCase(StringReplace(ALine, ' ', '', [rfReplaceAll]));
  Result := (Pos('freeandnil(' + LowerCase(AField) + ')', Line) > 0) or
    (Pos(LowerCase(AField) + '.free', Line) > 0) or (Pos(LowerCase(AField) + '.disposeof', Line) > 0);
end;

/// <summary>Vorhandener Destruktor Destroy der Klasse: Rumpf ABody (mehrzeilig) und ob die Klasse ihn deklariert.</summary>
function FindDestructor(ASource: TCommandSource; const AClass: TIndexSymbol; out ABody: TIndexSymbol;
  out ADeclared: Boolean): Boolean;
var
  Symbol: TIndexSymbol;
begin
  ABody := Default(TIndexSymbol);
  ADeclared := False;
  Result := False;
  for Symbol in ASource.UnitIndex.Symbols do
  begin
    if (Symbol.Kind = TIndexSymbolKind.Constructor_) and SameText(Symbol.Container, AClass.Name) and
      SameText(Symbol.Name, 'Destroy') then
    begin
      if (Symbol.Range.StartPos.Line > AClass.Range.StartPos.Line) and
        (Symbol.Range.EndPos.Line < AClass.Range.EndPos.Line) then
      begin
        ADeclared := True;
      end
      else if Symbol.Range.EndPos.Line > Symbol.Range.StartPos.Line then
      begin
        ABody := Symbol;
        Result := True;
      end;
    end;
  end;
end;

/// <summary>Ergänzt den vorhandenen Rumpf ABody um die Freigabe von AFields vor "inherited" bzw. vor "end".</summary>
function ExtendDestructor(ASource: TCommandSource; const AClass, ABody: TIndexSymbol; const AFields: TArray<string>;
  out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Missing: TArray<string>;
  Field, Text, Indent: string;
  Line, Target, Index: Integer;
  Freed: Boolean;
begin
  Missing := nil;
  for Field in AFields do
  begin
    Freed := False;
    for Line := ABody.Range.StartPos.Line to ABody.Range.EndPos.Line do
    begin
      if FreesField(ASource.Lines[Line], Field) then
      begin
        Freed := True;
      end;
    end;
    if not Freed then
    begin
      Missing := Missing + [Field];
    end;
  end;
  if Length(Missing) = 0 then
  begin
    Exit(Fail(Format('%s.Destroy gibt schon alle im Konstruktor erzeugten Felder frei', [AClass.Name]), AReason));
  end;
  // Vor dem ersten "inherited" im Rumpf, sonst vor dem abschließenden "end".
  Target := ABody.Range.EndPos.Line;
  for Line := ABody.Range.EndPos.Line downto ABody.Range.StartPos.Line do
  begin
    if StartsText('inherited', Trim(ASource.Lines[Line])) then
    begin
      Target := Line;
    end;
  end;
  Indent := ASource.Indent(Target);
  if Target = ABody.Range.EndPos.Line then
  begin
    Indent := Indent + '  ';
  end;
  Text := '';
  // In umgekehrter Reihenfolge der Erzeugung freigeben.
  for Index := High(Missing) downto 0 do
  begin
    if Text <> '' then
    begin
      Text := Text + ASource.LineBreak;
    end;
    Text := Text + Indent + Format('FreeAndNil(%s);', [Missing[Index]]);
  end;
  AEdits := [ASource.BeforeLine(Target, Text), ASource.RemoveCommand];
  Result := True;
end;

function ExecuteDtor(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol, Existing: TIndexSymbol;
  Fields: TArray<string>;
  Body: string;
  Index: Integer;
  Declared: Boolean;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
    begin
      Exit(Fail('/dtor gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    end;
    Fields := CreatedFields(Source, ClassSymbol.Name);
    // Vorhandenen Destruktor ergänzen statt einen zweiten anzulegen.
    if FindDestructor(Source, ClassSymbol, Existing, Declared) then
    begin
      Exit(ExtendDestructor(Source, ClassSymbol, Existing, Fields, AEdits, AReason));
    end;
    Body := Format('destructor %s.Destroy;', [ClassSymbol.Name]) + Source.LineBreak + 'begin';
    // In umgekehrter Reihenfolge der Erzeugung freigeben.
    for Index := High(Fields) downto 0 do
    begin
      Body := Body + Source.LineBreak + Format('  FreeAndNil(%s);', [Fields[Index]]);
    end;
    Body := Body + Source.LineBreak + '  inherited;' + Source.LineBreak + 'end;';
    if Declared then
    begin
      AEdits := [Source.AddBody(ClassSymbol.Name, Body), Source.RemoveCommand];
    end
    else
    begin
      AEdits := AddMethod(Source, ClassSymbol, 'public', 'destructor Destroy; override;', Body);
    end;
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /msg }

function ExecuteMsg(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Message, Name, RecordType: string;
begin
  AEdits := nil;
  Message := UpperCase(Trim(AContext.Arguments));
  if (Pos('_', Message) < 2) or not IsValidIdent(Message) then
  begin
    Exit(Fail('Erwartet wird /msg WM_NAME', AReason));
  end;
  Name := MessageMethodName(Message);
  RecordType := MessageRecord(Message);
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
    begin
      Exit(Fail('/msg gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    end;
    AEdits := AddMethod(Source, ClassSymbol, 'protected',
      Format('procedure %s(var Message: %s); message %s;', [Name, RecordType, Message]),
      Lines(Source, [Format('procedure %s.%s(var Message: %s);', [ClassSymbol.Name, Name, RecordType]), 'begin',
        '  inherited;', 'end;']));
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /override }

const
  VisibilityNames: array[TIndexVisibility] of string = ('public', 'published', 'protected', 'strict protected',
    'private', 'strict private');

/// <summary>Sucht eine virtuelle Methode AName in AUnit, Klasse AClassName; liefert auch den Vorfahren.</summary>
function FindInUnit(const AUnit: TUnitIndex; const AClassName, AName: string; out AMethod: TIndexSymbol;
  out AAncestor: string): Boolean;
var
  Symbol: TIndexSymbol;
begin
  AAncestor := '';
  Result := False;
  for Symbol in AUnit.Symbols do
  begin
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and SameText(Symbol.Name, AClassName) and
      (Length(Symbol.Ancestors) > 0) then
    begin
      AAncestor := Symbol.Ancestors[0];
    end;
  end;
  for Symbol in AUnit.Symbols do
  begin
    if (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and Symbol.IsVirtual and
      SameText(Symbol.Container, AClassName) and SameText(Symbol.Name, AName) then
    begin
      AMethod := Symbol;
      Exit(True);
    end;
  end;
end;

/// <summary>Datei einer anderen Unit; der Index kennt keine Parameterlisten.</summary>
function LoadText(const AFileName: string; out AText: string): Boolean;
var
  Format: TFileFormat;
begin
  try
    AText := TFileEncoding.LoadFromFile(AFileName, Format);
    Result := True;
  except
    on EInOutError do
      Result := False;
    on EFOpenError do
      Result := False;
  end;
end;

function RangeText(const ALines: TArray<string>; const ARange: TTextRange): string;
var
  Index: Integer;
begin
  if ARange.StartPos.Line = ARange.EndPos.Line then
  begin
    Exit(Copy(ALines[ARange.StartPos.Line], ARange.StartPos.Character + 1,
      ARange.EndPos.Character - ARange.StartPos.Character));
  end;
  Result := Copy(ALines[ARange.StartPos.Line], ARange.StartPos.Character + 1, MaxInt);
  for Index := ARange.StartPos.Line + 1 to ARange.EndPos.Line - 1 do
  begin
    Result := Result + ' ' + ALines[Index];
  end;
  Result := Result + ' ' + Copy(ALines[ARange.EndPos.Line], 1, ARange.EndPos.Character);
end;

/// <summary>Kopf der virtuellen Methode AName im ersten Vorfahren, der sie hat (Datei, dann Index).</summary>
function FindVirtual(ASource: TCommandSource; const AIndex: ISymbolIndex; const AClass: TIndexSymbol;
  const AName: string; out ASignature: string; out AVisibility: TIndexVisibility): Boolean;
var
  ClassName, Ancestor, Text: string;
  Method: TIndexSymbol;
  Location: TSymbolLocation;
  UnitIndex: TUnitIndex;
  Depth: Integer;
  Found: Boolean;
begin
  Result := False;
  if Length(AClass.Ancestors) = 0 then
  begin
    Exit;
  end;
  ClassName := AClass.Ancestors[0];
  for Depth := 1 to 32 do
  begin
    if FindInUnit(ASource.UnitIndex, ClassName, AName, Method, Ancestor) then
    begin
      ASignature := RoutineSignature(RangeText(ASource.Lines, Method.Range));
      AVisibility := Method.Visibility;
      Exit(True);
    end;
    if Ancestor = '' then
    begin
      // Klasse aus einer anderen Unit über den Index.
      if AIndex = nil then
      begin
        Exit;
      end;
      Found := False;
      for Location in AIndex.FindSymbols(ClassName) do
      begin
        if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and AIndex.FindFile(Location.FileName, UnitIndex) then
        begin
          Found := True;
          Break;
        end;
      end;
      if not Found then
      begin
        Exit;
      end;
      if FindInUnit(UnitIndex, ClassName, AName, Method, Ancestor) then
      begin
        if not LoadText(UnitIndex.FileName, Text) then
        begin
          Exit;
        end;
        ASignature := RoutineSignature(RangeText(Text.Replace(#13#10, #10).Split([#10]), Method.Range));
        AVisibility := Method.Visibility;
        Exit(True);
      end;
    end;
    if Ancestor = '' then
    begin
      Exit;
    end;
    ClassName := Ancestor;
  end;
end;

function ExecuteOverride(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Signature, Keyword, Rest, Arguments, Call: string;
  Visibility: TIndexVisibility;
  Space: Integer;
begin
  AEdits := nil;
  if not IsValidIdent(AContext.Arguments) then
  begin
    Exit(Fail('Erwartet wird /override Methodenname', AReason));
  end;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
    begin
      Exit(Fail('/override gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    end;
    if not FindVirtual(Source, AContext.Index, ClassSymbol, AContext.Arguments, Signature, Visibility) then
    begin
      Exit(Fail('Keine virtuelle Methode ' + AContext.Arguments + ' in den Vorfahren von ' + ClassSymbol.Name,
        AReason));
    end;
    // "procedure Paint" wird zu "procedure TFoo.Paint".
    Space := Pos(' ', Signature);
    Keyword := Copy(Signature, 1, Space - 1);
    Rest := Trim(Copy(Signature, Space + 1, MaxInt));
    if StartsText('class ', Signature) then
    begin
      Space := Pos(' ', Rest);
      Keyword := Keyword + ' ' + Copy(Rest, 1, Space - 1);
      Rest := Trim(Copy(Rest, Space + 1, MaxInt));
    end;
    Arguments := ParameterNames(Signature);
    if Arguments <> '' then
    begin
      Call := Format('inherited %s(%s)', [AContext.Arguments, Arguments]);
    end
    else
    begin
      Call := 'inherited ' + AContext.Arguments;
    end;
    if EndsText('function', Keyword) then
    begin
      Call := 'Result := ' + Call;
    end
    else if Arguments = '' then
    begin
      Call := 'inherited';
    end;
    AEdits := AddMethod(Source, ClassSymbol, VisibilityNames[Visibility], Signature + '; override;',
      Lines(Source, [Format('%s %s.%s;', [Keyword, ClassSymbol.Name, Rest]), 'begin', '  ' + Call + ';', 'end;']));
    Result := True;
  finally
    Source.Free;
  end;
end;

function CtorFields(const AContext: TSlashContext): TArray<string>;
var
  Source: TCommandSource;
  ClassSymbol, Symbol: TIndexSymbol;
begin
  Result := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
    begin
      Exit;
    end;
    for Symbol in Source.UnitIndex.Symbols do
    begin
      if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, ClassSymbol.Name) and
        (Symbol.TypeName <> '') then
      begin
        Result := Result + [Symbol.Name];
      end;
    end;
  finally
    Source.Free;
  end;
end;

/// <summary>Hängt die virtuellen Methoden von AClassName aus AUnit an AResult an, die weder in AOwn noch schon in
/// AResult stehen; AAncestor ist der erste Vorfahr von AClassName in AUnit ('' ohne).</summary>
procedure CollectVirtuals(const AUnit: TUnitIndex; const AClassName: string; const AOwn: TArray<string>;
  var AResult: TArray<string>; out AAncestor: string; out AFound: Boolean);
var
  Symbol: TIndexSymbol;
begin
  AAncestor := '';
  AFound := False;
  for Symbol in AUnit.Symbols do
  begin
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and SameText(Symbol.Name, AClassName) then
    begin
      AFound := True;
      if Length(Symbol.Ancestors) > 0 then
      begin
        AAncestor := Symbol.Ancestors[0];
      end;
    end;
  end;
  for Symbol in AUnit.Symbols do
  begin
    if (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and Symbol.IsVirtual and
      SameText(Symbol.Container, AClassName) and not MatchText(Symbol.Name, AOwn) and
      not MatchText(Symbol.Name, AResult) then
    begin
      AResult := AResult + [Symbol.Name];
    end;
  end;
end;

function OverrideCandidates(const AContext: TSlashContext): TArray<string>;
var
  Source: TCommandSource;
  ClassSymbol, Symbol: TIndexSymbol;
  Own: TArray<string>;
  ClassName, Ancestor: string;
  Location: TSymbolLocation;
  UnitIndex: TUnitIndex;
  Depth: Integer;
  Found: Boolean;
begin
  Result := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) or (Length(ClassSymbol.Ancestors) = 0) then
    begin
      Exit;
    end;
    // Was die Klasse schon deklariert, steht nicht zur Wahl.
    Own := nil;
    for Symbol in Source.UnitIndex.Symbols do
    begin
      if (Symbol.Kind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and
        SameText(Symbol.Container, ClassSymbol.Name) then
      begin
        Own := Own + [Symbol.Name];
      end;
    end;
    ClassName := ClassSymbol.Ancestors[0];
    for Depth := 1 to 32 do
    begin
      CollectVirtuals(Source.UnitIndex, ClassName, Own, Result, Ancestor, Found);
      if not Found then
      begin
        // Klasse aus einer anderen Unit über den Index, wie bei /override.
        if AContext.Index = nil then
        begin
          Exit;
        end;
        for Location in AContext.Index.FindSymbols(ClassName) do
        begin
          if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and
            AContext.Index.FindFile(Location.FileName, UnitIndex) then
          begin
            CollectVirtuals(UnitIndex, ClassName, Own, Result, Ancestor, Found);
            Break;
          end;
        end;
      end;
      if Ancestor = '' then
      begin
        Exit;
      end;
      ClassName := Ancestor;
    end;
  finally
    Source.Free;
  end;
end;

function MessageNames: TArray<string>;
var
  Entry: TMessageEntry;
begin
  Result := nil;
  for Entry in MessageTable do
  begin
    Result := Result + [Entry.Name];
  end;
end;

{ /intf }

/// <summary>Schlüssel einer fehlenden Methode zum Vergleich zweier Listen.</summary>
function MemberKey(const AMember: TResolvedSymbol): string;
begin
  Result := LowerCase(AMember.Container + '.' + AMember.Name + '(' + string.Join(',', AMember.ParamTypes) + ')');
end;

/// <summary>Name ohne Typargumente: IComparer&lt;TKunde&gt; wird IComparer.</summary>
function PlainName(const AName: string): string;
begin
  Result := AName;
  if Pos('<', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('<', Result) - 1);
  end;
end;

/// <summary>Änderung am Kopf der Klasse: ", AName" vor die schließende Klammer der Vorfahrenliste, ohne Liste
/// "(TInterfacedObject, AName)" hinter "class".</summary>
function HeaderEdit(ASource: TCommandSource; const AClass: TIndexSymbol; const AName: string;
  out AEdit: TTextEdit): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index, Depth: Integer;
begin
  Tokens := ASource.Tree.Tokens;
  Index := 0;
  while (Index <= High(Tokens)) and ((Tokens[Index].StartPos.Line < AClass.Range.StartPos.Line) or
    not Tokens[Index].IsKeyword('class')) do
  begin
    Inc(Index);
  end;
  if (Index > High(Tokens)) or (Tokens[Index].StartPos.Line > AClass.Range.EndPos.Line) then
  begin
    Exit(False);
  end;
  // class sealed / class abstract
  while (Index < High(Tokens)) and (Tokens[Index + 1].IsKeyword('sealed') or Tokens[Index + 1].IsKeyword('abstract') or
    SameText(Tokens[Index + 1].Text, 'sealed') or SameText(Tokens[Index + 1].Text, 'abstract')) do
  begin
    Inc(Index);
  end;
  if (Index < High(Tokens)) and Tokens[Index + 1].IsSymbol('(') then
  begin
    Depth := 0;
    for Index := Index + 1 to High(Tokens) do
    begin
      if Tokens[Index].IsSymbol('(') then
      begin
        Inc(Depth);
      end
      else if Tokens[Index].IsSymbol(')') then
      begin
        Dec(Depth);
        if Depth = 0 then
        begin
          AEdit := TTextEdit.Create(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].StartPos), ', ' + AName);
          Exit(True);
        end;
      end;
    end;
    Exit(False);
  end;
  AEdit := TTextEdit.Create(TTextRange.Create(Tokens[Index].EndPos, Tokens[Index].EndPos),
    '(TInterfacedObject, ' + AName + ')');
  Result := True;
end;

function ExecuteIntf(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Own: TUnitIndex;
  Name, TypeName, FileName, Section, Indent, Text: string;
  Header, Ancestors, Before, SourceLines: TArray<string>;
  Listed, NeedHeader: Boolean;
  Resolver: TNameResolver;
  Resolved: TResolvedSymbol;
  Missing, Known: TArray<TResolvedSymbol>;
  Member: TResolvedSymbol;
  Stub: TInterfaceStub;
  Edits: TArray<TTextEdit>;
  Edit: TTextEdit;
  EndLine, Index: Integer;
begin
  AEdits := nil;
  Name := Trim(AContext.Arguments);
  if not IsValidIdent(PlainName(Name), True) then
  begin
    Exit(Fail('Erwartet wird /intf IName', AReason));
  end;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) or (ClassSymbol.Range.StartPos.Line >= Source.Line) or
      (ClassSymbol.Range.EndPos.Line <= Source.Line) then
    begin
      Exit(Fail('/intf gilt nur in der Deklaration einer Klasse', AReason));
    end;
    TypeName := ClassSymbol.QualifiedName;
    FileName := '';
    if AContext.Uri <> '' then
    begin
      FileName := TDocumentUris.ToPath(AContext.Uri);
    end;
    Own := Source.UnitIndex;
    Own.FileName := FileName;
    Header := TInterfaceStubs.HeaderAncestors(Source.Lines, ClassSymbol.Range.StartPos.Line);
    Listed := False;
    Before := nil;
    for Text in Header do
    begin
      if SameText(PlainName(Text), PlainName(Name)) then
      begin
        Listed := True;
      end
      else
      begin
        Before := Before + [Text];
      end;
    end;
    if Header = nil then
    begin
      Before := ['TInterfacedObject'];
    end;
    Ancestors := Before + [Name];
    Resolver := TNameResolver.Create(AContext.Index);
    try
      Resolver.Namespaces := AContext.Namespaces;
      if not Resolver.ResolveNameFrom(Own, PlainName(Name), Resolved) or
        (Resolved.SymbolKind <> TIndexSymbolKind.InterfaceType) then
      begin
        Exit(Fail(Format('%s ist kein bekanntes Interface', [Name]), AReason));
      end;
      // Nur die Methoden von AName samt Vorfahren: was schon ohne AName fehlt, bleibt außen vor.
      Known := Resolver.MissingInterfaceMembers(Own, TypeName, Before);
      Missing := nil;
      for Member in Resolver.MissingInterfaceMembers(Own, TypeName, Ancestors) do
      begin
        Index := 0;
        while (Index <= High(Known)) and (MemberKey(Known[Index]) <> MemberKey(Member)) do
        begin
          Inc(Index);
        end;
        if Index > High(Known) then
        begin
          Missing := Missing + [Member];
        end;
      end;
    finally
      Resolver.Free;
    end;
    if Listed and (Length(Missing) = 0) then
    begin
      Exit(Fail(Format('%s hängt schon an %s und ist vollständig implementiert', [Name, ClassSymbol.Name]),
        AReason));
    end;
    Section := '';
    if AContext.Host <> nil then
    begin
      Section := LowerCase(Trim(AContext.Host.Setting(AContext.Uri, TSlashSettings.InterfaceSection)));
    end;
    if (Section <> 'private') and (Section <> 'protected') then
    begin
      Section := 'public';
    end;
    EndLine := ClassSymbol.Range.EndPos.Line;
    Indent := Source.Indent(EndLine);
    NeedHeader := TInterfaceStubs.LastSection(Source.Tree.Tokens, ClassSymbol.Range.StartPos.Line, EndLine) <> Section;
    Edits := nil;
    for Member in Missing do
    begin
      if (Member.FileName = '') or SameText(Member.FileName, FileName) then
      begin
        SourceLines := Source.Lines;
      end
      else if LoadText(Member.FileName, Text) then
      begin
        SourceLines := Text.Replace(#13, '').Split([#10]);
      end
      else
      begin
        Continue;
      end;
      if not TInterfaceStubs.Make(TInterfaceStubs.GenericName(Member.Container, Member.Bindings), TypeName,
        TInterfaceStubs.SubstituteWords(TInterfaceStubs.DeclarationOf(SourceLines, Member.Range), Member.Bindings),
        Source.LineBreak, Stub) then
      begin
        Continue;
      end;
      Edits := Edits + TInterfaceStubs.ClassEdits(Stub, EndLine, Indent, Section, NeedHeader, Source.LineBreak);
      if TClassCompletion.BodyEdit(Source.Tree, Source.Text, TypeName, Stub.Body, Edit) then
      begin
        Edits := Edits + [Edit];
      end
      else
      begin
        Edits := Edits + [Source.AddBody(TypeName, Stub.Body)];
      end;
    end;
    if not Listed then
    begin
      if not HeaderEdit(Source, ClassSymbol, Name, Edit) then
      begin
        Exit(Fail(Format('Der Kopf von %s lässt sich nicht erweitern', [ClassSymbol.Name]), AReason));
      end;
      Edits := [Edit] + Edits;
    end;
    AEdits := TInterfaceStubs.Merge(Edits) + [Source.RemoveCommand];
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

procedure RegisterClassCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('impl', 'Fehlende Methodenrümpfe der Klasse anlegen', '/impl', ExecuteImpl));
  ARegister(Command('ctor', 'Konstruktor mit den Feldern als Parametern', '/ctor owner', ExecuteCtor));
  ARegister(Command('dtor', 'Destruktor, der erzeugte Felder freigibt', '/dtor', ExecuteDtor));
  ARegister(Command('override', 'Virtuelle Methode eines Vorfahren überschreiben', '/override Paint',
    ExecuteOverride));
  ARegister(Command('msg', 'Botschaftsmethode anlegen', '/msg WM_SIZE', ExecuteMsg));
  ARegister(Command('intf', 'Interface an die Klasse hängen und seine Methoden anlegen', '/intf IExporter',
    ExecuteIntf));
end;

end.
