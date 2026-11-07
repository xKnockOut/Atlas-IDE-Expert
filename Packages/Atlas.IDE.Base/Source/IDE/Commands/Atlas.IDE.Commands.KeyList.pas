unit Atlas.IDE.Commands.KeyList;

// Liste der Tasten der Editorbefehle (#399), aus der TAtlasIdeEditorKeys
// (Atlas.IDE.Commands.Bindings) seine Tastaturbindung der IDE baut. Jede Taste
// wird vor dem Aufnehmen auf Konflikte geprüft (#494); ohne Vorrang bleibt eine
// fremde Belegung aktiv. Bound sammelt die belegten Tasten, damit Rebind die
// Bindung nur bei einer Änderung neu anmeldet.

interface

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard;

type
  /// <summary>Eine Taste der Editorbefehle.</summary>
  TAtlasEditorKey = record
    Key: Word;
    /// <summary>Sicherung (#493), unter der die Taste läuft: Fehler anderer Funktionen schalten sie nicht ab.
    /// </summary>
    Feature: TAtlasFeature;
    Proc: TProc;
    /// <summary>Statt Proc: sofort ausführen; False gibt die Taste an die nächste Bindung weiter.</summary>
    Attempt: TFunc<Boolean>;
  end;

  /// <summary>Tasten der Editorbefehle, nach Konfliktprüfung aufgenommen.</summary>
  TAtlasEditorKeyList = class
  private
    FKeys: TArray<TAtlasEditorKey>;
    FBound: string;
    /// <summary>Taste schon aufgenommen?</summary>
    function Has(AKey: Word): Boolean;
    procedure Append(AFeature: TAtlasFeature; AKey: Word; const AProc: TProc; const AAttempt: TFunc<Boolean>);
  protected
    /// <summary>Alle Tasten verwerfen (vor dem Neubelegen).</summary>
    procedure Clear;
  public
    /// <summary>AFeature: Sicherung, unter der die Taste läuft.</summary>
    procedure AddKey(AFeature: TAtlasFeature; AKey: Integer; const AWhat: string; const AProc: TProc);
    /// <summary>Wie AddKey mit eigenem Vorrang statt des gemeinsamen (Zurück/Vor, #504). Eigener Name statt
    /// Überladung: anonyme Methoden als Argument vertragen keine Überladungen.</summary>
    procedure AddPriorityKey(AFeature: TAtlasFeature; AKey: Integer; const AWhat: string; const AProc: TProc;
      APriority: Boolean);
    /// <summary>ACheck False: ohne Konfliktprüfung, weil die Taste ohne Treffer ohnehin an die IDE
    /// weitergeht.</summary>
    procedure AddAttemptKey(AFeature: TAtlasFeature; AKey: Integer; const AWhat: string;
      const AAttempt: TFunc<Boolean>; ACheck: Boolean); overload;
    /// <summary>Wie oben mit Konfliktprüfung (ACheck = True).</summary>
    procedure AddAttemptKey(AFeature: TAtlasFeature; AKey: Integer; const AWhat: string;
      const AAttempt: TFunc<Boolean>); overload;
    /// <summary>Wie AddAttemptKey mit Konfliktprüfung und eigenem Vorrang (#1104).</summary>
    procedure AddPriorityAttemptKey(AFeature: TAtlasFeature; AKey: Integer; const AWhat: string;
      const AAttempt: TFunc<Boolean>; APriority: Boolean);
    property Keys: TArray<TAtlasEditorKey> read FKeys;
    /// <summary>Belegte Tasten als Text („Taste;Taste;“), '' ohne.</summary>
    property Bound: string read FBound;
  end;

implementation

uses
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Keys;

function TAtlasEditorKeyList.Has(AKey: Word): Boolean;
var
  mExisting: TAtlasEditorKey;
begin
  Result := False;
  for mExisting in FKeys do
  begin
    if mExisting.Key = AKey then
    begin
      Exit(True);
    end;
  end;
end;

procedure TAtlasEditorKeyList.Append(AFeature: TAtlasFeature; AKey: Word; const AProc: TProc;
  const AAttempt: TFunc<Boolean>);
var
  mKey: TAtlasEditorKey;
begin
  mKey.Key := AKey;
  mKey.Feature := AFeature;
  mKey.Proc := AProc;
  mKey.Attempt := AAttempt;
  FKeys := FKeys + [mKey];
  FBound := FBound + IntToStr(AKey) + ';';
end;

procedure TAtlasEditorKeyList.Clear;
begin
  FKeys := nil;
  FBound := '';
end;

procedure TAtlasEditorKeyList.AddKey(AFeature: TAtlasFeature; AKey: Integer; const AWhat: string;
  const AProc: TProc);
begin
  AddPriorityKey(AFeature, AKey, AWhat, AProc, TAtlasIdeSettings.Current.EditorKeysPriority);
end;

procedure TAtlasEditorKeyList.AddPriorityKey(AFeature: TAtlasFeature; AKey: Integer; const AWhat: string;
  const AProc: TProc; APriority: Boolean);
begin
  if TAtlasIdeKeys.Decide(Word(AKey), APriority, AWhat) then
  begin
    Append(AFeature, Word(AKey), AProc, nil);
  end;
end;

procedure TAtlasEditorKeyList.AddAttemptKey(AFeature: TAtlasFeature; AKey: Integer; const AWhat: string;
  const AAttempt: TFunc<Boolean>);
begin
  AddAttemptKey(AFeature, AKey, AWhat, AAttempt, True);
end;

procedure TAtlasEditorKeyList.AddAttemptKey(AFeature: TAtlasFeature; AKey: Integer; const AWhat: string;
  const AAttempt: TFunc<Boolean>; ACheck: Boolean);
begin
  // 0 = keine Taste; dieselbe Taste zweimal (beide Felder gleich belegt) nur einmal binden.
  if (AKey = 0) or Has(Word(AKey)) then
  begin
    Exit;
  end;
  if ACheck and not TAtlasIdeKeys.Decide(Word(AKey), TAtlasIdeSettings.Current.EditorKeysPriority, AWhat) then
  begin
    Exit;
  end;
  Append(AFeature, Word(AKey), nil, AAttempt);
end;

procedure TAtlasEditorKeyList.AddPriorityAttemptKey(AFeature: TAtlasFeature; AKey: Integer; const AWhat: string;
  const AAttempt: TFunc<Boolean>; APriority: Boolean);
begin
  if (AKey = 0) or Has(Word(AKey)) then
  begin
    Exit;
  end;
  if TAtlasIdeKeys.Decide(Word(AKey), APriority, AWhat) then
  begin
    Append(AFeature, Word(AKey), nil, AAttempt);
  end;
end;

end.
