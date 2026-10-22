unit Atlas.Common.Editing.ClassActions;

// Klassen-Aktionen als Code-Aktionen (#42), mit denselben Erzeugern wie die
// Schnellbefehle und die Vervollständigung:
//   - "Getter, Setter und Feld für Name erzeugen" auf "property Name: Typ;"
//     ohne read/write: Feld FName, GetName und SetName (derselbe Setter wie
//     /prop) in einem private-Abschnitt vor der Property, Rümpfe hinter der
//     letzten Methode der Klasse
//   - "Methoden von IFoo implementieren" für jedes Interface im Kopf der
//     Klasse, dem noch Methoden fehlen (Erzeuger von /intf, #466)
//   - "Name überschreiben" für jede virtuelle Methode der Vorfahren, die die
//     Klasse noch nicht deklariert (Erzeuger von /override, Auswahl wie im
//     Erzeugen-Menü #719), höchstens MaxOverrides
//   - "Name anlegen" für ein fehlendes Feld F<Name>, Get<Name> oder Set<Name>
//     hinter read/write einer Property (Erzeuger der Vervollständigung #467,
//     Korrektur der Regel property-accessor-invalid #1001)
// Angeboten wird in der Deklaration einer Klasse (Kopfzeile bis vor "end").
// /intf und /override laufen über eine gedachte Befehlszeile hinter der
// Cursorzeile; ihre Änderungen werden auf den Text ohne diese Zeile
// zurückgerechnet.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.AccessorCreation;

type
  /// <summary>Umgebung der Klassen-Aktionen: Index für Vorfahren und Interfaces aus anderen Units, Formatstil.</summary>
  TClassActionContext = record
    Index: ISymbolIndex;
    Namespaces: TArray<string>;
    DelphiVersion: string;
    Uri: string;
    Style: TFormatStyle;
    /// <summary>Für die Einstellungen der Erzeuger (z. B. Abschnitt der Interface-Methoden); nil ohne.</summary>
    Host: ISlashHost;
    class function Default: TClassActionContext; static;
  end;

  TClassActions = class
  public const
    MaxOverrides = 20;
  public
    /// <summary>Alle Klassen-Aktionen für Zeile ALine; leer außerhalb einer Klassendeklaration.</summary>
    class function Actions(const AText: string; ATree: TSyntaxTree; ALine: Integer;
      const AContext: TClassActionContext): TArray<TCodeAction>; static;
    /// <summary>Getter, Setter und Feld zur Property in Zeile ALine; False, wenn dort keine Property ohne
    /// read/write steht oder alles schon da ist.</summary>
    class function PropertyAccessors(const AText: string; ALine: Integer; const AContext: TClassActionContext;
      out AAction: TCodeAction): Boolean; static;
    /// <summary>Fehlende Methoden von AInterface; False, wenn es kein Interface ist oder nichts fehlt.</summary>
    class function ImplementInterface(const AText: string; ALine: Integer; const AInterface: string;
      const AContext: TClassActionContext; out AAction: TCodeAction): Boolean; static;
    /// <summary>Virtuelle Methode AName eines Vorfahren überschreiben.</summary>
    class function OverrideMethod(const AText: string; ALine: Integer; const AName: string;
      const AContext: TClassActionContext; out AAction: TCodeAction): Boolean; static;
    /// <summary>Fehlendes Feld bzw. fehlende Zugriffsmethode APlan der Property in Zeile ALine anlegen (#1001);
    /// False, wenn es das Mitglied schon gibt oder ALine in keiner Klasse liegt.</summary>
    class function CreateAccessor(const AText: string; ALine: Integer; const APlan: TAccessorPlan;
      const AContext: TClassActionContext; out AAction: TCodeAction): Boolean; static;
    /// <summary>Überschreibbare Methoden der Vorfahren, die die Klasse um ALine noch nicht deklariert.</summary>
    class function OverrideCandidates(const AText: string; ALine: Integer;
      const AContext: TClassActionContext): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.RegularExpressions,
  Atlas.Common.Editing.ClassCommands,
  Atlas.Common.Editing.ClassMembers,
  Atlas.Common.Editing.CommandSource,
  Atlas.Common.Editing.InterfaceStubs,
  Atlas.Text.Lines;

{ TClassActionContext }

class function TClassActionContext.Default: TClassActionContext;
begin
  Result := System.Default(TClassActionContext);
  Result.Style := TFormatStyle.Default;
end;

/// <summary>Typdeklaration einer Klasse, deren Kopfzeile bis vor "end" ALine enthält; nil sonst.</summary>
function ClassDeclAt(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode;
var
  Found: TSyntaxNode;
begin
  Found := nil;
  if (ATree <> nil) and (ATree.Root <> nil) then
    ATree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if (ANode.StartPos.Line > ALine) or (ANode.EndPos.Line < ALine) then
          Exit(False);
        if (ANode.Kind = TSyntaxKind.TypeDecl) and (ANode.FindChild(TSyntaxKind.ClassType) <> nil) and
          (ANode.EndPos.Line > ALine) then
          Found := ANode;
        Result := True;
      end);
  Result := Found;
end;

/// <summary>AText mit der Befehlszeile ACommand hinter Zeile ALine.</summary>
function PhantomText(const AText: string; ALine: Integer; const ACommand: string): string;
var
  Lines: TArray<string>;
  LB: string;
  Index: Integer;
begin
  Lines := TTextLines.SplitLines(AText);
  LB := TTextLines.LineBreakOf(AText);
  Result := '';
  for Index := 0 to High(Lines) do
  begin
    if Index > 0 then
      Result := Result + LB;
    Result := Result + Lines[Index];
    if Index = ALine then
      Result := Result + LB + TTextLines.IndentOf(Lines[Index]) + '  ' + ACommand;
  end;
end;

/// <summary>Position im Text mit Befehlszeile APhantom zurück auf den Text ohne sie.</summary>
function MapBack(const APosition: TTextPosition; APhantom: Integer): TTextPosition;
begin
  if APosition.Line < APhantom then
    Result := APosition
  else if APosition.Line = APhantom then
    Result := TTextPosition.Create(APhantom, 0)
  else
    Result := TTextPosition.Create(APosition.Line - 1, APosition.Character);
end;

/// <summary>Führt ACommand als gedachte Zeile hinter ALine aus und rechnet die Änderungen zurück.</summary>
function RunPhantom(const AText: string; ALine: Integer; const ACommand: string; const AContext: TClassActionContext;
  out AEdits: TArray<TTextEdit>): Boolean;
var
  Phantom, Reason: string;
  Edits: TArray<TTextEdit>;
  Edit: TTextEdit;
  Line: Integer;
begin
  AEdits := nil;
  Phantom := PhantomText(AText, ALine, ACommand);
  Line := ALine + 1;
  Result := TSlashCommandRegistry.Shared.Run(Phantom, Line, 0, AContext.Namespaces, nil, AContext.Index,
    AContext.DelphiVersion, AContext.Uri, AContext.Host, AContext.Style, Edits, Reason);
  if not Result then
    Exit;
  for Edit in Edits do
  begin
    // Das Entfernen der Befehlszeile entfällt: Im echten Text gibt es sie nicht.
    if (Edit.NewText = '') and (Edit.Range.StartPos.Line = Line) and (Edit.Range.StartPos.Character = 0) and
      (Edit.Range.EndPos.Line = Line + 1) and (Edit.Range.EndPos.Character = 0) then
      Continue;
    AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(MapBack(Edit.Range.StartPos, Line),
      MapBack(Edit.Range.EndPos, Line)), Edit.NewText)];
  end;
  Result := AEdits <> nil;
end;

function SlashContext(const AText: string; ALine: Integer; const AContext: TClassActionContext): TSlashContext;
var
  Lines: TArray<string>;
begin
  Lines := TTextLines.SplitLines(AText);
  Result := System.Default(TSlashContext);
  Result.Text := AText;
  Result.Line := ALine;
  if (ALine >= 0) and (ALine <= High(Lines)) then
    Result.LineText := Lines[ALine];
  Result.Namespaces := AContext.Namespaces;
  Result.Index := AContext.Index;
  Result.DelphiVersion := AContext.DelphiVersion;
  Result.Style := AContext.Style;
  Result.Uri := AContext.Uri;
  Result.Host := AContext.Host;
end;

function HasMember(const AUnit: TUnitIndex; const AClassName, AName: string): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in AUnit.Symbols do
    if SameText(Symbol.Container, AClassName) and SameText(Symbol.Name, AName) then
      Exit(True);
  Result := False;
end;

{ TClassActions }

class function TClassActions.PropertyAccessors(const AText: string; ALine: Integer;
  const AContext: TClassActionContext; out AAction: TCodeAction): Boolean;
var
  Lines: TArray<string>;
  Match: TMatch;
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Name, TypeName, Field, Getter, Setter, LB, Indent, Section, Declarations, Bodies, Comment: string;
  Edits: TArray<TTextEdit>;
begin
  AAction := Default(TCodeAction);
  Result := False;
  Lines := TTextLines.SplitLines(AText);
  if (ALine < 0) or (ALine > High(Lines)) then
    Exit;
  Match := TRegEx.Match(Lines[ALine], '^(\s*)property\s+(\w+)\s*:\s*([^;]+?)\s*;\s*(//.*|)$', [roIgnoreCase]);
  if not Match.Success or TRegEx.IsMatch(Match.Groups[3].Value,
    '\b(read|write|index|default|stored|nodefault|implements)\b', [roIgnoreCase]) then
    Exit;
  Name := Match.Groups[2].Value;
  TypeName := Match.Groups[3].Value;
  Comment := Match.Groups[4].Value;
  Field := 'F' + Name;
  Getter := 'Get' + Name;
  Setter := 'Set' + Name;
  // Die Property-Zeile gilt als Befehlszeile: Der Baum sieht sie nicht, sie wird ohnehin ersetzt.
  Source := TCommandSource.Create(SlashContext(AText, ALine, AContext));
  try
    if not Source.ClassAt(ClassSymbol) or (ClassSymbol.Range.StartPos.Line >= ALine) or
      (ClassSymbol.Range.EndPos.Line <= ALine) then
      Exit;
    LB := Source.LineBreak;
    Indent := Source.Indent(ClassSymbol.Range.EndPos.Line);
    Section := TInterfaceStubs.LastSection(Source.Tree.Tokens, ClassSymbol.Range.StartPos.Line, ALine);
    if Section = '' then
      Section := 'public';
    // Feld und Zugriffsmethoden vor der Property: Delphi verlangt sie vor ihrer Verwendung, und Felder stehen in
    // einem Abschnitt vor den Methoden. Danach geht der Abschnitt der Property weiter.
    Declarations := '';
    if not HasMember(Source.UnitIndex, ClassSymbol.Name, Field) then
      Declarations := Declarations + Indent + '  ' + Format('%s: %s;', [Field, TypeName]) + LB;
    Bodies := '';
    if not HasMember(Source.UnitIndex, ClassSymbol.Name, Getter) then
    begin
      Declarations := Declarations + Indent + '  ' + Format('function %s: %s;', [Getter, TypeName]) + LB;
      Bodies := Format('function %s.%s: %s;', [ClassSymbol.Name, Getter, TypeName]) + LB + 'begin' + LB +
        '  Result := ' + Field + ';' + LB + 'end;';
    end;
    if not HasMember(Source.UnitIndex, ClassSymbol.Name, Setter) then
    begin
      Declarations := Declarations + Indent + '  ' + Format('procedure %s(const Value: %s);', [Setter, TypeName]) + LB;
      if Bodies <> '' then
        Bodies := Bodies + LB + LB;
      // Derselbe Setter wie bei /prop: nur bei Änderung, mit Benachrichtigung.
      Bodies := Bodies + Format('procedure %s.%s(const Value: %s);', [ClassSymbol.Name, Setter, TypeName]) + LB +
        TSetterGenerator.Body(Field, 'Value', TSetterGenerator.NotifyCall(Source, AContext.Index, ClassSymbol), LB);
    end;
    if Declarations = '' then
      Exit;
    if Comment <> '' then
      Comment := ' ' + Comment;
    Edits := [TTextEdit.Create(TTextRange.Create(ALine, 0, ALine, Length(Lines[ALine])),
      Indent + 'private' + LB + Declarations + Indent + Section + LB + Match.Groups[1].Value +
      Format('property %s: %s read %s write %s;', [Name, TypeName, Getter, Setter]) + Comment)];
    if Bodies <> '' then
      Edits := Edits + [Source.AddBody(ClassSymbol.Name, Bodies)];
  finally
    Source.Free;
  end;
  AAction.Title := Format('Getter, Setter und Feld für %s erzeugen', [Name]);
  AAction.Kind := RewriteKind;
  AAction.Edits := TSlashCommandRegistry.Reindent(AText, Edits, AContext.Style);
  Result := True;
end;

class function TClassActions.ImplementInterface(const AText: string; ALine: Integer; const AInterface: string;
  const AContext: TClassActionContext; out AAction: TCodeAction): Boolean;
begin
  AAction := Default(TCodeAction);
  Result := RunPhantom(AText, ALine, '/intf ' + AInterface, AContext, AAction.Edits);
  if Result then
  begin
    AAction.Title := Format('Methoden von %s implementieren', [AInterface]);
    AAction.Kind := RewriteKind;
  end;
end;

class function TClassActions.OverrideMethod(const AText: string; ALine: Integer; const AName: string;
  const AContext: TClassActionContext; out AAction: TCodeAction): Boolean;
begin
  AAction := Default(TCodeAction);
  Result := RunPhantom(AText, ALine, '/override ' + AName, AContext, AAction.Edits);
  if Result then
  begin
    AAction.Title := Format('%s überschreiben', [AName]);
    AAction.Kind := RewriteKind;
  end;
end;

class function TClassActions.CreateAccessor(const AText: string; ALine: Integer; const APlan: TAccessorPlan;
  const AContext: TClassActionContext; out AAction: TCodeAction): Boolean;
var
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Edits: TArray<TTextEdit>;
  WithField: Boolean;
begin
  AAction := Default(TCodeAction);
  // Die Property-Zeile gilt als Befehlszeile wie in der Vervollständigung; sie bleibt unverändert.
  Source := TCommandSource.Create(SlashContext(AText, ALine, AContext));
  try
    Result := Source.ClassAt(ClassSymbol) and TAccessorCreation.Edits(Source, AContext.Index, ClassSymbol, APlan,
      Edits, WithField);
  finally
    Source.Free;
  end;
  if not Result then
    Exit;
  AAction.Title := Format('%s anlegen', [APlan.Name]);
  AAction.Kind := RewriteKind;
  AAction.Edits := TSlashCommandRegistry.Reindent(AText, Edits, AContext.Style);
end;

class function TClassActions.OverrideCandidates(const AText: string; ALine: Integer;
  const AContext: TClassActionContext): TArray<string>;
var
  Phantom: string;
begin
  Phantom := PhantomText(AText, ALine, '/override');
  Result := Atlas.Common.Editing.ClassCommands.OverrideCandidates(SlashContext(Phantom, ALine + 1, AContext));
end;

class function TClassActions.Actions(const AText: string; ATree: TSyntaxTree; ALine: Integer;
  const AContext: TClassActionContext): TArray<TCodeAction>;
var
  Decl: TSyntaxNode;
  Action: TCodeAction;
  Name: string;
  Count: Integer;
begin
  Result := nil;
  Decl := ClassDeclAt(ATree, ALine);
  if Decl = nil then
    Exit;
  if PropertyAccessors(AText, ALine, AContext, Action) then
    Result := Result + [Action];
  for Name in TInterfaceStubs.HeaderAncestors(TTextLines.SplitLines(AText), Decl.StartPos.Line) do
    if TRegEx.IsMatch(Name, '^I[A-Z]') and ImplementInterface(AText, ALine, Name, AContext, Action) then
      Result := Result + [Action];
  Count := 0;
  for Name in OverrideCandidates(AText, ALine, AContext) do
  begin
    if Count >= MaxOverrides then
      Break;
    if OverrideMethod(AText, ALine, Name, AContext, Action) then
    begin
      Result := Result + [Action];
      Inc(Count);
    end;
  end;
end;

end.
