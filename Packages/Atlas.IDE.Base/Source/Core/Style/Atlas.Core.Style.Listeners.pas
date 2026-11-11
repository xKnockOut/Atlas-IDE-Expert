unit Atlas.Core.Style.Listeners;

// Abonnenten des Themenwechsels (#2061): Fenster, Dialoge und Steuerelemente
// melden sich mit einem Besitzer und einem Rückruf an und beim Freigeben
// wieder ab. Notify ruft alle zur Zeit des Aufrufs angemeldeten Rückrufe in
// Reihenfolge der Anmeldung; wer sich währenddessen abmeldet (ein Dialog
// schließt sich), wird nicht mehr gerufen, wer sich währenddessen anmeldet,
// erst beim nächsten Wechsel. Ein fehlerhafter Rückruf hält die übrigen nicht
// auf; Notify liefert seine Fehlermeldung für das Protokoll.
// Ohne VCL, damit die Logik unter Free Pascal getestet werden kann.

interface

uses
  System.SysUtils;

type
  TAtlasThemeListeners = class
  private type
    TEntry = record
      Owner: TObject;
      Handler: TProc;
    end;
  private
    FEntries: TArray<TEntry>;
    function IndexOf(AOwner: TObject): Integer;
  public
    destructor Destroy; override;
    /// <summary>AHandler für AOwner anmelden; ein zweiter Aufruf mit demselben Besitzer ersetzt den Rückruf.
    /// Ohne Besitzer oder Rückruf geschieht nichts.</summary>
    procedure Add(AOwner: TObject; const AHandler: TProc);
    /// <summary>Rückruf von AOwner abmelden; unbekannte Besitzer werden übergangen.</summary>
    procedure Remove(AOwner: TObject);
    /// <summary>True, wenn AOwner angemeldet ist.</summary>
    function Contains(AOwner: TObject): Boolean;
    /// <summary>Anzahl der angemeldeten Besitzer.</summary>
    function Count: Integer;
    /// <summary>Alle angemeldeten Rückrufe rufen; liefert je fehlgeschlagenem Rückruf „Klasse: Meldung“.</summary>
    function Notify: TArray<string>;
  end;

implementation

{ TAtlasThemeListeners }

destructor TAtlasThemeListeners.Destroy;
begin
  FEntries := nil;
  inherited;
end;

function TAtlasThemeListeners.IndexOf(AOwner: TObject): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(FEntries) do
  begin
    if FEntries[mIndex].Owner = AOwner then
    begin
      Exit(mIndex);
    end;
  end;
end;

procedure TAtlasThemeListeners.Add(AOwner: TObject; const AHandler: TProc);
var
  mIndex: Integer;
  mEntry: TEntry;
begin
  if (AOwner = nil) or not Assigned(AHandler) then
  begin
    Exit;
  end;
  mIndex := IndexOf(AOwner);
  if mIndex >= 0 then
  begin
    FEntries[mIndex].Handler := AHandler;
    Exit;
  end;
  mEntry.Owner := AOwner;
  mEntry.Handler := AHandler;
  FEntries := FEntries + [mEntry];
end;

procedure TAtlasThemeListeners.Remove(AOwner: TObject);
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AOwner);
  if mIndex >= 0 then
  begin
    Delete(FEntries, mIndex, 1);
  end;
end;

function TAtlasThemeListeners.Contains(AOwner: TObject): Boolean;
begin
  Result := IndexOf(AOwner) >= 0;
end;

function TAtlasThemeListeners.Count: Integer;
begin
  Result := Length(FEntries);
end;

function TAtlasThemeListeners.Notify: TArray<string>;
var
  mSnapshot: TArray<TEntry>;
  mEntry: TEntry;
begin
  Result := nil;
  // Kopie: Rückrufe dürfen sich und andere ab- oder neu anmelden.
  mSnapshot := Copy(FEntries);
  for mEntry in mSnapshot do
  begin
    // Inzwischen abgemeldet: Der Besitzer kann schon freigegeben sein.
    if not Contains(mEntry.Owner) then
    begin
      Continue;
    end;
    try
      mEntry.Handler();
    except
      // lsp-ignore: catch-all-without-raise -- ein Abonnent hält die übrigen nicht auf; Meldung geht an den Aufrufer
      on E: Exception do
        Result := Result + [E.ClassName + ': ' + E.Message];
    end;
  end;
end;

end.
