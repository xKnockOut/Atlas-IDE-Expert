unit Atlas.Core.Commands.KeyMap;

// Tastenkürzel-Übersicht mit Konflikterkennung (#520), Teil ohne VCL und Open
// Tools API. Die IDE-Schicht sammelt alle Belegungen als TAtlasKeyItem:
// Aktionen der IDE und anderer Erweiterungen (INTAServices.ActionList),
// Tastaturbelegungen des Editors (IOTAKeyboardServices, soweit auslesbar) und
// die Tasten von Atlas (TAtlasKeyEntry.AllFromSettings, #399, #494, #502).
// Hier entsteht daraus die Übersicht:
// - Konflikt: dieselbe Taste, sich überschneidender Kontext (global
//   überschneidet sich mit allem) und verschiedene Besitzer (Herkunft, bei
//   Atlas die Funktion, bei Erweiterungen der Package-Name). Doppelte
//   Belegungen innerhalb der IDE sind ihre eigene Sache und kein Konflikt.
// - Wer gewinnt, entscheidet der Kontext, in dem sich die Belegungen treffen:
//   auf der Willkommensseite das Suchfeld von Atlas; im Editor eine
//   Tastaturbelegung vor einem Menübefehl, unter mehreren die wirksame
//   (zuletzt angemeldete); Atlas mit Vorrang vor der fremden Belegung; ohne
//   Vorrang überlässt Atlas die Taste (#494); unter Aktionen die erste der
//   Aktionsliste.
// - Suche nach Taste („Strg+Umschalt+P“, auch englisch „Ctrl+Shift+P“, nur
//   Umschalttasten „Strg+Alt“) oder nach Text in Taste, Befehl, Kategorie und
//   Herkunft.
// - Export als druckbare HTML-Seite (Zeilen mit Konflikt rot).
// - AtlasConflicts liefert die Atlas-Tasten mit offenem Konflikt für die
//   Meldung beim Start und die Einrichtung (#625).
// - „Units suchen“ übernimmt Strg+F12 (#777): Die Taste bleibt bei der Aktion
//   der IDE; die Übersicht zeigt die Aktion als Atlas-Zeile (Quelle Action,
//   Kontext global), solange die Übernahme an ist.

interface

uses
  System.SysUtils,
  Atlas.Core.Commands.KeyConflicts;

type
  {$SCOPEDENUMS ON}
  /// <summary>Wem die Belegung gehört.</summary>
  TAtlasKeyOrigin = (Ide, Atlas, Plugin);
  /// <summary>Wo die Taste wirkt; Global überschneidet sich mit jedem anderen Kontext.</summary>
  TAtlasKeyContext = (Global, Editor, Designer, WelcomePage);
  /// <summary>Action: Aktion mit Tastenkürzel (Menü, wirkt im ganzen Hauptfenster); Binding: Tastaturbelegung des
  /// Editors (IOTAKeyboardBinding); Window: Kürzel eines eigenen Fensters (Suchfeld der Willkommensseite).</summary>
  TAtlasKeySource = (Action, Binding, Window);
  /// <summary>Warum der Gewinner eines Konflikts gewinnt.</summary>
  TAtlasKeyReason = (None, AtlasPriority, AtlasYields, EditorBinding, LastBinding, FirstAction, OwnWindow,
    NoneActive);
  {$SCOPEDENUMS OFF}

  /// <summary>Eine Belegung einer Taste.</summary>
  TAtlasKeyItem = record
    ShortCut: Word;
    /// <summary>Taste als Text, wie die IDE sie zeigt (ShortCutToText).</summary>
    KeyText: string;
    Command: string;
    /// <summary>Kategorie bzw. Menüpfad; '' ohne.</summary>
    Category: string;
    Origin: TAtlasKeyOrigin;
    /// <summary>„IDE“, „Atlas“ oder der Package-Name der Erweiterung (ohne Pfad).</summary>
    OriginName: string;
    Context: TAtlasKeyContext;
    Source: TAtlasKeySource;
    /// <summary>Eindeutig je Quelle: Name der Aktion, Atlas-Funktion, Taste der Tastaturbelegung.</summary>
    Id: string;
    /// <summary>Reihenfolge in der Quelle (Aktionsliste, Anmeldung).</summary>
    Order: Integer;
    /// <summary>Hält die Taste: Atlas nur, wenn frei oder mit Vorrang belegt (#494); sonst immer True.</summary>
    Active: Boolean;
    /// <summary>Atlas: Vorrang gewählt („Atlas verwenden“).</summary>
    Priority: Boolean;
    /// <summary>Wirksame Tastaturbelegung des Editors für diese Taste (Abfrage der IDE).</summary>
    Effective: Boolean;
    /// <summary>Nur bei Herkunft Atlas: die Funktion.</summary>
    Func: TAtlasKeyFunction;
    /// <summary>Ergebnis von Analyze: mindestens eine andere Belegung kollidiert.</summary>
    Conflict: Boolean;
    /// <summary>Ergebnis von Analyze: Index der Belegung, die im gemeinsamen Kontext gewinnt; -1 = keine.</summary>
    Winner: Integer;
    Wins: Boolean;
    Reason: TAtlasKeyReason;
    /// <summary>Aufrufe des Befehls per Maus bzw. über das Kürzel (#600, Spalte „Selten per Tastatur“); 0 ohne
    /// Zählung.</summary>
    MouseUses: Integer;
    KeyUses: Integer;
    class function Create(AShortCut: Word; const AKeyText, ACommand: string; AOrigin: TAtlasKeyOrigin;
      const AOriginName: string; AContext: TAtlasKeyContext; ASource: TAtlasKeySource; const AId: string;
      AOrder: Integer): TAtlasKeyItem; static;
    /// <summary>„Befehl (Herkunft)“ für Meldungen.</summary>
    function Holder: string;
    /// <summary>Selten per Tastatur genutzt (TAtlasCommandUsage.IsRarelyByKeyboard).</summary>
    function RarelyByKeyboard: Boolean;
  end;

  /// <summary>Suche in der Übersicht.</summary>
  TAtlasKeyQuery = record
    /// <summary>Kleingeschrieben und ohne Leerraum am Rand.</summary>
    Text: string;
    /// <summary>Erkannte Taste; 0 = keine.</summary>
    ShortCut: Word;
    /// <summary>Nur Umschalttasten erkannt („Strg+Umschalt“); 0 = keine.</summary>
    Modifiers: Word;
    class function Parse(const AText: string): TAtlasKeyQuery; static;
    function IsEmpty: Boolean;
    function Matches(const AItem: TAtlasKeyItem): Boolean;
  end;

  /// <summary>Zeile der HTML-Übersicht: Zellen als Klartext.</summary>
  TAtlasKeyHtmlRow = record
    Cells: TArray<string>;
    Conflict: Boolean;
    class function Create(const ACells: TArray<string>; AConflict: Boolean): TAtlasKeyHtmlRow; static;
  end;

  TAtlasKeyMap = class
  public const
    IdeName = 'IDE';
    AtlasName = 'Atlas';
    scShift = TAtlasKeyConflicts.scShift;
    scCtrl = TAtlasKeyConflicts.scCtrl;
    scAlt = TAtlasKeyConflicts.scAlt;
    ModifierMask = scShift or scCtrl or scAlt;
  public
    /// <summary>Kontext einer Atlas-Taste: das Suchfeld auf der Willkommensseite, Strg+F12 für „Units suchen“
    /// global (Aktion der IDE), alle übrigen im Editor (Tastaturbelegungen wirken nur dort).</summary>
    class function ContextOf(AFunc: TAtlasKeyFunction): TAtlasKeyContext; static;
    /// <summary>Window für das Suchfeld, Action für Strg+F12 (#777), sonst Binding.</summary>
    class function SourceOf(AFunc: TAtlasKeyFunction): TAtlasKeySource; static;
    /// <summary>Befehl der Befehlspalette (#502) zu einer Atlas-Taste; '' ohne. Mehrere Tasten können denselben
    /// Befehl haben (beide Tasten von Deklaration ⇄ Implementierung, eigene Taste und Strg+F12 für „Units
    /// suchen“).</summary>
    class function CommandIdOf(AFunc: TAtlasKeyFunction): string; static;
    /// <summary>Kontext einer Aktion nach ihrer Kategorie: „Designer“/„Formular“ = Designer, „Editor“ = Editor,
    /// sonst global (Menübefehle wirken im ganzen Hauptfenster).</summary>
    class function ContextOfCategory(const ACategory: string): TAtlasKeyContext; static;
    /// <summary>Herkunft nach dem Modul, das die Belegung umsetzt: Atlas-Package, Ordner der IDE (bds.exe) oder
    /// eine andere Erweiterung; AName ist dann der Package-Name ohne Pfad und Endung.</summary>
    class function OriginOfModule(const AModule, AIdeFolder, AAtlasModule: string;
      out AName: string): TAtlasKeyOrigin; static;
    class function Overlaps(A, B: TAtlasKeyContext): Boolean; static;
    /// <summary>A und B belegen dieselbe Taste in sich überschneidendem Kontext und gehören verschiedenen
    /// Besitzern.</summary>
    class function Collide(const A, B: TAtlasKeyItem): Boolean; static;
    /// <summary>Konflikte, Gewinner und Grund für jede Belegung setzen.</summary>
    class procedure Analyze(var AItems: TArray<TAtlasKeyItem>); static;
    /// <summary>Belegungen mit Konflikt.</summary>
    class function ConflictCount(const AItems: TArray<TAtlasKeyItem>): Integer; static;
    /// <summary>Andere Belegung im Konflikt mit AItems[AIndex]: der Gewinner, wenn es nicht sie selbst ist,
    /// sonst die erste kollidierende; -1 ohne Konflikt.</summary>
    class function PartnerOf(const AItems: TArray<TAtlasKeyItem>; AIndex: Integer): Integer; static;
    /// <summary>Atlas-Tasten mit offenem Konflikt: kollidiert und nicht mit Vorrang gewonnen (#520, #625).</summary>
    class function AtlasConflicts(const AItems: TArray<TAtlasKeyItem>): TArray<Integer>; static;
    /// <summary>Indizes der Belegungen zur Suche, sortiert nach Taste und Befehl.</summary>
    class function Filter(const AItems: TArray<TAtlasKeyItem>; const AQuery: string;
      AOnlyConflicts: Boolean): TArray<Integer>; static;
    /// <summary>Taste aus Text: Umschalttasten deutsch oder englisch, dann eine Taste; 0, wenn nicht erkannt.
    /// AModifiers bekommt die Umschalttasten auch ohne Taste.</summary>
    class function ParseShortCut(const AText: string; out AModifiers: Word): Word; static;
    /// <summary>Druckbare HTML-Seite: Titel, Unterzeile, Knopf „Drucken“, Tabelle; Zeilen mit Konflikt rot.</summary>
    class function Html(const ALanguage, ATitle, ASubtitle, APrint: string; const AHeaders: TArray<string>;
      const ARows: TArray<TAtlasKeyHtmlRow>): string; static;
    class function HtmlEscape(const AText: string): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Commands.Usage;

{ TAtlasKeyItem }

class function TAtlasKeyItem.Create(AShortCut: Word; const AKeyText, ACommand: string; AOrigin: TAtlasKeyOrigin;
  const AOriginName: string; AContext: TAtlasKeyContext; ASource: TAtlasKeySource; const AId: string;
  AOrder: Integer): TAtlasKeyItem;
begin
  Result := Default(TAtlasKeyItem);
  Result.ShortCut := AShortCut;
  Result.KeyText := AKeyText;
  Result.Command := ACommand;
  Result.Origin := AOrigin;
  Result.OriginName := AOriginName;
  Result.Context := AContext;
  Result.Source := ASource;
  Result.Id := AId;
  Result.Order := AOrder;
  Result.Active := True;
  Result.Winner := -1;
end;

function TAtlasKeyItem.RarelyByKeyboard: Boolean;
begin
  Result := TAtlasCommandUsage.IsRarelyByKeyboard(MouseUses, KeyUses);
end;

function TAtlasKeyItem.Holder: string;
begin
  if OriginName = '' then
    Result := Command
  else
    Result := Command + ' (' + OriginName + ')';
end;

{ TAtlasKeyQuery }

class function TAtlasKeyQuery.Parse(const AText: string): TAtlasKeyQuery;
begin
  Result := Default(TAtlasKeyQuery);
  Result.Text := LowerCase(Trim(AText));
  Result.ShortCut := TAtlasKeyMap.ParseShortCut(AText, Result.Modifiers);
end;

function TAtlasKeyQuery.IsEmpty: Boolean;
begin
  Result := Text = '';
end;

function TAtlasKeyQuery.Matches(const AItem: TAtlasKeyItem): Boolean;
begin
  if Text = '' then
    Exit(True);
  if ShortCut <> 0 then
    Exit(AItem.ShortCut = ShortCut);
  if Modifiers <> 0 then
    Exit((AItem.ShortCut <> 0) and ((AItem.ShortCut and Modifiers) = Modifiers));
  Result := (Pos(Text, LowerCase(AItem.KeyText)) > 0) or (Pos(Text, LowerCase(AItem.Command)) > 0) or
    (Pos(Text, LowerCase(AItem.Category)) > 0) or (Pos(Text, LowerCase(AItem.OriginName)) > 0);
end;

{ TAtlasKeyHtmlRow }

class function TAtlasKeyHtmlRow.Create(const ACells: TArray<string>; AConflict: Boolean): TAtlasKeyHtmlRow;
begin
  Result.Cells := ACells;
  Result.Conflict := AConflict;
end;

{ TAtlasKeyMap }

class function TAtlasKeyMap.ContextOf(AFunc: TAtlasKeyFunction): TAtlasKeyContext;
begin
  case AFunc of
    TAtlasKeyFunction.WelcomeSearch, TAtlasKeyFunction.WelcomeQuickBuild, TAtlasKeyFunction.WelcomeQuickTests:
      Result := TAtlasKeyContext.WelcomePage;
    TAtlasKeyFunction.UnitSearchIde:
      Result := TAtlasKeyContext.Global;
  else
    Result := TAtlasKeyContext.Editor;
  end;
end;

class function TAtlasKeyMap.SourceOf(AFunc: TAtlasKeyFunction): TAtlasKeySource;
begin
  case AFunc of
    TAtlasKeyFunction.WelcomeSearch, TAtlasKeyFunction.WelcomeQuickBuild, TAtlasKeyFunction.WelcomeQuickTests:
      Result := TAtlasKeySource.Window;
    TAtlasKeyFunction.UnitSearchIde:
      Result := TAtlasKeySource.Action;
  else
    Result := TAtlasKeySource.Binding;
  end;
end;

class function TAtlasKeyMap.CommandIdOf(AFunc: TAtlasKeyFunction): string;
begin
  case AFunc of
    TAtlasKeyFunction.Check:
      Result := 'Atlas.CheckNow';
    TAtlasKeyFunction.QuickToggle:
      Result := 'Atlas.QuickToggles';
    TAtlasKeyFunction.CodeActions:
      Result := 'Atlas.CodeActions';
    TAtlasKeyFunction.ExpandSelection:
      Result := 'Atlas.ExpandSelection';
    TAtlasKeyFunction.ShrinkSelection:
      Result := 'Atlas.ShrinkSelection';
    TAtlasKeyFunction.GoToImplementation:
      Result := 'Atlas.Implementations';
    TAtlasKeyFunction.TypeDefinition:
      Result := 'Atlas.TypeDefinition';
    TAtlasKeyFunction.UndoChange:
      Result := 'Atlas.UndoChange';
    TAtlasKeyFunction.RedoChange:
      Result := 'Atlas.RedoChange';
    TAtlasKeyFunction.MethodToggleUp, TAtlasKeyFunction.MethodToggleDown:
      Result := 'Atlas.ToggleMethod';
    TAtlasKeyFunction.TestUnit:
      Result := 'Atlas.SwitchTestUnit';
    TAtlasKeyFunction.UnitSearch, TAtlasKeyFunction.UnitSearchIde:
      Result := 'Atlas.UnitSearch';
    TAtlasKeyFunction.Bookmark:
      Result := 'Atlas.BookmarkAdd';
    TAtlasKeyFunction.GenerateMenu:
      Result := 'Atlas.GenerateMenu';
    TAtlasKeyFunction.Notifications:
      Result := 'Atlas.Notifications';
    TAtlasKeyFunction.HideElement:
      Result := 'Atlas.HideElement';
    TAtlasKeyFunction.NextProblem:
      Result := 'Atlas.NextProblem';
    TAtlasKeyFunction.PreviousProblem:
      Result := 'Atlas.PreviousProblem';
    TAtlasKeyFunction.QuickOpen:
      Result := 'Atlas.QuickOpen';
    TAtlasKeyFunction.NavBack:
      Result := 'Atlas.NavBack';
    TAtlasKeyFunction.NavForward:
      Result := 'Atlas.NavForward';
    TAtlasKeyFunction.LastEdit:
      Result := 'Atlas.LastEdit';
    TAtlasKeyFunction.PeekDefinition:
      Result := 'Atlas.PeekDefinition';
    TAtlasKeyFunction.PeekReferences:
      Result := 'Atlas.PeekReferences';
    TAtlasKeyFunction.Breadcrumbs:
      Result := 'Atlas.Breadcrumbs';
  else
    Result := '';
  end;
end;

class function TAtlasKeyMap.ContextOfCategory(const ACategory: string): TAtlasKeyContext;
var
  Lower: string;
begin
  Lower := LowerCase(ACategory);
  if (Pos('designer', Lower) > 0) or (Pos('formular', Lower) > 0) then
    Result := TAtlasKeyContext.Designer
  else if Pos('editor', Lower) > 0 then
    Result := TAtlasKeyContext.Editor
  else
    Result := TAtlasKeyContext.Global;
end;

class function TAtlasKeyMap.OriginOfModule(const AModule, AIdeFolder, AAtlasModule: string;
  out AName: string): TAtlasKeyOrigin;
var
  Folder, Name: string;
begin
  // Kein Pfad nach außen: nur der Package-Name einer Erweiterung.
  Name := ExtractFileName(AModule.Replace('/', '\'));
  if (AAtlasModule <> '') and SameText(AModule, AAtlasModule) then
  begin
    AName := AtlasName;
    Exit(TAtlasKeyOrigin.Atlas);
  end;
  Folder := IncludeTrailingPathDelimiter(AIdeFolder.Replace('/', '\'));
  if (AModule = '') or ((AIdeFolder <> '') and AModule.Replace('/', '\').StartsWith(Folder, True)) then
  begin
    AName := IdeName;
    Exit(TAtlasKeyOrigin.Ide);
  end;
  AName := ChangeFileExt(Name, '');
  Result := TAtlasKeyOrigin.Plugin;
end;

class function TAtlasKeyMap.Overlaps(A, B: TAtlasKeyContext): Boolean;
begin
  Result := (A = B) or (A = TAtlasKeyContext.Global) or (B = TAtlasKeyContext.Global);
end;

class function TAtlasKeyMap.Collide(const A, B: TAtlasKeyItem): Boolean;
begin
  Result := False;
  if (A.ShortCut = 0) or (A.ShortCut <> B.ShortCut) or not Overlaps(A.Context, B.Context) then
    Exit;
  if A.Origin <> B.Origin then
    Exit(True);
  case A.Origin of
    // Zwei Atlas-Funktionen auf derselben Taste: doppelt belegt.
    TAtlasKeyOrigin.Atlas:
      Result := A.Id <> B.Id;
    TAtlasKeyOrigin.Plugin:
      Result := not SameText(A.OriginName, B.OriginName);
  else
    // Belegungen innerhalb der IDE sind ihre eigene Sache.
    Result := False;
  end;
end;

/// <summary>Kontext, in dem sich AItems[AIndex] mit den Partnern trifft: der eigene, bei globalen Belegungen der
/// engste der Partner (Editor vor Designer vor Willkommensseite).</summary>
function ClashContext(const AItems: TArray<TAtlasKeyItem>; AIndex: Integer;
  const APartners: TArray<Integer>): TAtlasKeyContext;
var
  Partner: Integer;
  Found: Boolean;
  Context: TAtlasKeyContext;
begin
  Result := AItems[AIndex].Context;
  if Result <> TAtlasKeyContext.Global then
    Exit;
  for Context in [TAtlasKeyContext.Editor, TAtlasKeyContext.Designer, TAtlasKeyContext.WelcomePage] do
  begin
    Found := False;
    for Partner in APartners do
      if AItems[Partner].Context = Context then
        Found := True;
    if Found then
      Exit(Context);
  end;
end;

/// <summary>Gewinner unter ACandidates im Kontext AClash; -1, wenn keine die Taste hält.</summary>
procedure Decide(const AItems: TArray<TAtlasKeyItem>; const ACandidates: TArray<Integer>;
  AClash: TAtlasKeyContext; out AWinner: Integer; out AReason: TAtlasKeyReason);
var
  Candidate: Integer;
  OnlyAtlasLeft, ActionLoses: Boolean;
begin
  AWinner := -1;
  AReason := TAtlasKeyReason.NoneActive;
  // Willkommensseite: Das Suchfeld von Atlas nimmt die Taste, solange die Seite aktiv ist.
  if AClash = TAtlasKeyContext.WelcomePage then
    for Candidate in ACandidates do
      if (AItems[Candidate].Source = TAtlasKeySource.Window) and AItems[Candidate].Active then
      begin
        AWinner := Candidate;
        AReason := TAtlasKeyReason.OwnWindow;
        Exit;
      end;
  // Editor: Tastaturbelegungen vor Menübefehlen; unter ihnen die wirksame (zuletzt angemeldete).
  if AClash = TAtlasKeyContext.Editor then
  begin
    for Candidate in ACandidates do
      if (AWinner < 0) and (AItems[Candidate].Source = TAtlasKeySource.Binding) and AItems[Candidate].Active and
        AItems[Candidate].Effective then
        AWinner := Candidate;
    for Candidate in ACandidates do
      if (AWinner < 0) and (AItems[Candidate].Source = TAtlasKeySource.Binding) and AItems[Candidate].Active and
        (AItems[Candidate].Origin = TAtlasKeyOrigin.Atlas) and AItems[Candidate].Priority then
        AWinner := Candidate;
    for Candidate in ACandidates do
      if (AItems[Candidate].Source = TAtlasKeySource.Binding) and AItems[Candidate].Active and
        ((AWinner < 0) or ((AItems[AWinner].Source = TAtlasKeySource.Binding) and
        not AItems[AWinner].Effective and not AItems[AWinner].Priority and
        (AItems[Candidate].Order > AItems[AWinner].Order))) then
        AWinner := Candidate;
  end;
  // Sonst die erste Aktion der Aktionsliste.
  if AWinner < 0 then
    for Candidate in ACandidates do
      if (AItems[Candidate].Source = TAtlasKeySource.Action) and AItems[Candidate].Active and
        ((AWinner < 0) or (AItems[Candidate].Order < AItems[AWinner].Order)) then
        AWinner := Candidate;
  if AWinner < 0 then
    Exit;
  OnlyAtlasLeft := AItems[AWinner].Origin <> TAtlasKeyOrigin.Atlas;
  ActionLoses := False;
  for Candidate in ACandidates do
    if Candidate <> AWinner then
    begin
      if (AItems[Candidate].Origin <> TAtlasKeyOrigin.Atlas) or AItems[Candidate].Active then
        OnlyAtlasLeft := False;
      if AItems[Candidate].Source = TAtlasKeySource.Action then
        ActionLoses := True;
    end;
  if OnlyAtlasLeft then
    AReason := TAtlasKeyReason.AtlasYields
  else if (AItems[AWinner].Origin = TAtlasKeyOrigin.Atlas) and AItems[AWinner].Priority and
    (AItems[AWinner].Source = TAtlasKeySource.Binding) then
    AReason := TAtlasKeyReason.AtlasPriority
  else if AItems[AWinner].Source = TAtlasKeySource.Binding then
  begin
    if ActionLoses then
      AReason := TAtlasKeyReason.EditorBinding
    else
      AReason := TAtlasKeyReason.LastBinding;
  end
  else
    AReason := TAtlasKeyReason.FirstAction;
end;

class procedure TAtlasKeyMap.Analyze(var AItems: TArray<TAtlasKeyItem>);
var
  Index, Other, Winner: Integer;
  Partners, Candidates: TArray<Integer>;
  Clash: TAtlasKeyContext;
  Reason: TAtlasKeyReason;
begin
  for Index := 0 to High(AItems) do
  begin
    AItems[Index].Conflict := False;
    AItems[Index].Winner := -1;
    AItems[Index].Wins := False;
    AItems[Index].Reason := TAtlasKeyReason.None;
  end;
  for Index := 0 to High(AItems) do
  begin
    if AItems[Index].ShortCut = 0 then
      Continue;
    Partners := nil;
    for Other := 0 to High(AItems) do
      if (Other <> Index) and Collide(AItems[Index], AItems[Other]) then
        Partners := Partners + [Other];
    if Length(Partners) = 0 then
    begin
      AItems[Index].Winner := Index;
      AItems[Index].Wins := AItems[Index].Active;
      Continue;
    end;
    AItems[Index].Conflict := True;
    Clash := ClashContext(AItems, Index, Partners);
    Candidates := [Index];
    for Other in Partners do
      if Overlaps(AItems[Other].Context, Clash) then
        Candidates := Candidates + [Other];
    Decide(AItems, Candidates, Clash, Winner, Reason);
    AItems[Index].Winner := Winner;
    AItems[Index].Reason := Reason;
    AItems[Index].Wins := Winner = Index;
  end;
end;

class function TAtlasKeyMap.ConflictCount(const AItems: TArray<TAtlasKeyItem>): Integer;
var
  Item: TAtlasKeyItem;
begin
  Result := 0;
  for Item in AItems do
    if Item.Conflict then
      Inc(Result);
end;

class function TAtlasKeyMap.PartnerOf(const AItems: TArray<TAtlasKeyItem>; AIndex: Integer): Integer;
var
  Other: Integer;
begin
  Result := -1;
  if (AIndex < 0) or (AIndex > High(AItems)) or not AItems[AIndex].Conflict then
    Exit;
  if (AItems[AIndex].Winner >= 0) and (AItems[AIndex].Winner <> AIndex) then
    Exit(AItems[AIndex].Winner);
  for Other := 0 to High(AItems) do
    if (Other <> AIndex) and Collide(AItems[AIndex], AItems[Other]) then
      Exit(Other);
end;

class function TAtlasKeyMap.AtlasConflicts(const AItems: TArray<TAtlasKeyItem>): TArray<Integer>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to High(AItems) do
    if (AItems[Index].Origin = TAtlasKeyOrigin.Atlas) and AItems[Index].Conflict and
      not (AItems[Index].Wins and AItems[Index].Priority) then
      Result := Result + [Index];
end;

class function TAtlasKeyMap.Filter(const AItems: TArray<TAtlasKeyItem>; const AQuery: string;
  AOnlyConflicts: Boolean): TArray<Integer>;
var
  Query: TAtlasKeyQuery;
  Found: TList<Integer>;
  Index: Integer;
  Items: TArray<TAtlasKeyItem>;
begin
  Items := AItems;
  Query := TAtlasKeyQuery.Parse(AQuery);
  Found := TList<Integer>.Create;
  try
    for Index := 0 to High(Items) do
      if (not AOnlyConflicts or Items[Index].Conflict) and Query.Matches(Items[Index]) then
        Found.Add(Index);
    Found.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result := CompareText(Items[A].KeyText, Items[B].KeyText);
        if Result = 0 then
          Result := Integer(Items[A].ShortCut) - Integer(Items[B].ShortCut);
        if Result = 0 then
          Result := CompareText(Items[A].Command, Items[B].Command);
        if Result = 0 then
          Result := A - B;
      end));
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

/// <summary>Umschalttaste zum Namen (deutsch oder englisch); 0, wenn es keine ist.</summary>
function ModifierOf(const AName: string): Word;
begin
  if (AName = 'strg') or (AName = 'ctrl') or (AName = 'control') or (AName = 'ctl') then
    Result := TAtlasKeyMap.scCtrl
  else if (AName = 'umschalt') or (AName = 'umsch') or (AName = 'shift') or (AName = 'shft') then
    Result := TAtlasKeyMap.scShift
  else if (AName = 'alt') or (AName = 'menu') then
    Result := TAtlasKeyMap.scAlt
  else
    Result := 0;
end;

/// <summary>Virtueller Tastencode zum Namen (deutsch oder englisch); 0, wenn unbekannt. AFunctionKey bei F1–F24.
/// </summary>
function KeyOf(const AName: string; out AFunctionKey: Boolean): Word;
var
  Number: Integer;
begin
  AFunctionKey := False;
  Result := 0;
  if AName = '' then
    Exit;
  if Length(AName) = 1 then
  begin
    case AName[1] of
      'a'..'z':
        Exit(Ord(UpCase(AName[1])));
      '0'..'9':
        Exit(Ord(AName[1]));
      '.':
        Exit($BE);
      ',':
        Exit($BC);
      '-':
        Exit($BD);
    end;
    Exit;
  end;
  if (AName[1] = 'f') and TryStrToInt(Copy(AName, 2, MaxInt), Number) and (Number >= 1) and (Number <= 24) then
  begin
    AFunctionKey := True;
    Exit($70 + Number - 1);
  end;
  if (AName = 'leer') or (AName = 'leertaste') or (AName = 'space') then
    Result := $20
  else if (AName = 'eingabe') or (AName = 'enter') or (AName = 'return') then
    Result := $0D
  else if (AName = 'esc') or (AName = 'escape') then
    Result := $1B
  else if (AName = 'tab') or (AName = 'tabulator') then
    Result := $09
  else if (AName = 'entf') or (AName = 'del') or (AName = 'delete') then
    Result := $2E
  else if (AName = 'einfg') or (AName = 'ins') or (AName = 'insert') then
    Result := $2D
  else if (AName = 'pos1') or (AName = 'home') then
    Result := $24
  else if (AName = 'ende') or (AName = 'end') then
    Result := $23
  else if (AName = 'bild auf') or (AName = 'bildauf') or (AName = 'pgup') or (AName = 'page up') or
    (AName = 'pageup') then
    Result := $21
  else if (AName = 'bild ab') or (AName = 'bildab') or (AName = 'pgdn') or (AName = 'page down') or
    (AName = 'pagedown') then
    Result := $22
  else if (AName = 'rück') or (AName = 'rücktaste') or (AName = 'backspace') or (AName = 'bksp') then
    Result := $08
  else if (AName = 'links') or (AName = 'left') then
    Result := $25
  else if (AName = 'oben') or (AName = 'auf') or (AName = 'up') then
    Result := $26
  else if (AName = 'rechts') or (AName = 'right') then
    Result := $27
  else if (AName = 'unten') or (AName = 'ab') or (AName = 'down') then
    Result := $28;
end;

class function TAtlasKeyMap.ParseShortCut(const AText: string; out AModifiers: Word): Word;
var
  Parts: TArray<string>;
  Index: Integer;
  Part: string;
  Modifier, Key: Word;
  FunctionKey: Boolean;
begin
  Result := 0;
  AModifiers := 0;
  Parts := LowerCase(Trim(AText)).Split(['+']);
  if Length(Parts) = 0 then
    Exit;
  for Index := 0 to High(Parts) do
  begin
    Part := Trim(Parts[Index]);
    if (Part = '') and (Index = High(Parts)) and (Index > 0) then
      // „Strg+“: nur Umschalttasten.
      Exit;
    Modifier := ModifierOf(Part);
    if Modifier <> 0 then
    begin
      AModifiers := AModifiers or Modifier;
      Continue;
    end;
    // Eine Taste nur am Ende.
    Key := KeyOf(Part, FunctionKey);
    if (Key = 0) or (Index <> High(Parts)) then
    begin
      AModifiers := 0;
      Exit;
    end;
    // Ein einzelnes Zeichen ohne Umschalttaste ist eine Textsuche, eine Funktionstaste nicht.
    if (Length(Parts) = 1) and not FunctionKey then
      Exit;
    Result := Key or AModifiers;
  end;
end;

class function TAtlasKeyMap.HtmlEscape(const AText: string): string;
var
  Builder: TStringBuilder;
  Ch: Char;
begin
  Builder := TStringBuilder.Create;
  try
    for Ch in AText do
      case Ch of
        '&':
          Builder.Append('&amp;');
        '<':
          Builder.Append('&lt;');
        '>':
          Builder.Append('&gt;');
        '"':
          Builder.Append('&quot;');
        '''':
          Builder.Append('&#39;');
      else
        Builder.Append(Ch);
      end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TAtlasKeyMap.Html(const ALanguage, ATitle, ASubtitle, APrint: string;
  const AHeaders: TArray<string>; const ARows: TArray<TAtlasKeyHtmlRow>): string;
var
  Builder: TStringBuilder;
  Header: string;
  Row: TAtlasKeyHtmlRow;
  Index: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('<!DOCTYPE html>'#13#10'<html lang="').Append(HtmlEscape(ALanguage)).Append('">'#13#10);
    Builder.Append('<head>'#13#10'<meta charset="utf-8">'#13#10);
    Builder.Append('<title>').Append(HtmlEscape(ATitle)).Append('</title>'#13#10);
    Builder.Append('<style>'#13#10 +
      'body{font:13px "Segoe UI",Arial,sans-serif;color:#1f2328;margin:24px}'#13#10 +
      'h1{font-size:20px;margin:0 0 4px}'#13#10 +
      'p.sub{color:#59636e;margin:0 0 12px}'#13#10 +
      'button.print{margin:0 0 12px;padding:4px 12px}'#13#10 +
      'table{border-collapse:collapse;width:100%}'#13#10 +
      'th,td{text-align:left;padding:4px 8px;border-bottom:1px solid #d1d9e0;vertical-align:top}'#13#10 +
      'th{background:#f6f8fa}'#13#10 +
      'td.key{font-family:Consolas,"Courier New",monospace;white-space:nowrap}'#13#10 +
      'tr.conflict td{color:#cf222e}'#13#10 +
      'tr.conflict td.key{font-weight:600}'#13#10 +
      '@media print{body{margin:0}button.print{display:none}thead{display:table-header-group}' +
      'tr{page-break-inside:avoid}tr.conflict td{color:#cf222e;-webkit-print-color-adjust:exact;' +
      'print-color-adjust:exact}}'#13#10 +
      '</style>'#13#10'</head>'#13#10'<body>'#13#10);
    Builder.Append('<h1>').Append(HtmlEscape(ATitle)).Append('</h1>'#13#10);
    if ASubtitle <> '' then
      Builder.Append('<p class="sub">').Append(HtmlEscape(ASubtitle)).Append('</p>'#13#10);
    if APrint <> '' then
      Builder.Append('<button class="print" onclick="window.print()">').Append(HtmlEscape(APrint))
        .Append('</button>'#13#10);
    Builder.Append('<table>'#13#10'<thead><tr>');
    for Header in AHeaders do
      Builder.Append('<th>').Append(HtmlEscape(Header)).Append('</th>');
    Builder.Append('</tr></thead>'#13#10'<tbody>'#13#10);
    for Row in ARows do
    begin
      if Row.Conflict then
        Builder.Append('<tr class="conflict">')
      else
        Builder.Append('<tr>');
      for Index := 0 to High(Row.Cells) do
      begin
        if Index = 0 then
          Builder.Append('<td class="key">')
        else
          Builder.Append('<td>');
        Builder.Append(HtmlEscape(Row.Cells[Index])).Append('</td>');
      end;
      Builder.Append('</tr>'#13#10);
    end;
    Builder.Append('</tbody>'#13#10'</table>'#13#10'</body>'#13#10'</html>'#13#10);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

end.
