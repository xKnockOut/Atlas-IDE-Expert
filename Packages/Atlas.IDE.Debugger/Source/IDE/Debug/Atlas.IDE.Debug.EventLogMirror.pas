unit Atlas.IDE.Debug.EventLogMirror;

// Ereignisprotokoll (#580): liest neue Zeilen aus dem Fenster
// „Ereignisprotokoll“ der IDE mit. Die Open Tools API meldet Ausgaben von
// OutputDebugString und Haltepunkt-Meldungen nicht; das Fenster der IDE hat
// sie. Gesucht wird ein Formular, dessen Name oder Klasse „EventLog“ enthält,
// darin die erste Liste (TCustomListBox bzw. TCustomListView). StartSession
// merkt die Zeilenzahl, NewLines liefert nur Zeilen danach; wird die Liste
// kürzer (geleert), beginnt es vorn. Was gefunden wurde, steht einmal je
// Sitzung im Diagnoseprotokoll, damit sich eine abweichende IDE erkennen
// lässt. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls;

type
  /// <summary>Komponente nur für die Freigabemeldung: Schließt die IDE ihr Fenster, vergisst der Spiegel die Liste.
  /// </summary>
  TAtlasIdeEventLogMirror = class(TComponent)
  private
    FList: TWinControl;
    FRead: Integer;
    function Find(out ADetails: string): TWinControl;
    function LineCount: Integer;
    function Line(AIndex: Integer): string;
    procedure Follow(AList: TWinControl);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    destructor Destroy; override;
    /// <summary>Liste suchen, vorhandene Zeilen überspringen; ALog bekommt das Ergebnis der Suche.</summary>
    procedure StartSession(const ALog: TProc<string>);
    /// <summary>Zeilen seit dem letzten Aufruf; ohne gefundene Liste keine.</summary>
    function NewLines: TArray<string>;
  end;

implementation

uses
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ComCtrls;

const
  cFormMark = 'EVENTLOG';
  cFormDetail = ' form %s (%s): %s;';
  cListDetail = ' list %s (%s)';

function IsList(AControl: TControl): Boolean;
begin
  Result := (AControl is TCustomListBox) or (AControl is TCustomListView);
end;

/// <summary>Erste Liste unter AParent (Tiefensuche); AClasses sammelt die Klassen der Steuerelemente.</summary>
function FirstList(AParent: TWinControl; AClasses: TStringBuilder): TWinControl;
var
  mIndex: Integer;
  mControl: TControl;
begin
  Result := nil;
  for mIndex := 0 to AParent.ControlCount - 1 do
  begin
    mControl := AParent.Controls[mIndex];
    AClasses.Append(' ').Append(mControl.ClassName);
    if IsList(mControl) then
    begin
      Exit(TWinControl(mControl));
    end;
    if mControl is TWinControl then
    begin
      Result := FirstList(TWinControl(mControl), AClasses);
      if Result <> nil then
      begin
        Exit;
      end;
    end;
  end;
end;

function TAtlasIdeEventLogMirror.Find(out ADetails: string): TWinControl;
var
  mIndex: Integer;
  mForm: TCustomForm;
  mClasses, mDetails: TStringBuilder;
begin
  Result := nil;
  mDetails := TStringBuilder.Create;
  mClasses := TStringBuilder.Create;
  try
    for mIndex := 0 to Screen.CustomFormCount - 1 do
    begin
      mForm := Screen.CustomForms[mIndex];
      if (Pos(cFormMark, UpperCase(mForm.Name)) = 0) and (Pos(cFormMark, UpperCase(mForm.ClassName)) = 0) then
      begin
        Continue;
      end;
      mClasses.Clear;
      Result := FirstList(mForm, mClasses);
      mDetails.AppendFormat(cFormDetail, [mForm.Name, mForm.ClassName, Trim(mClasses.ToString)]);
      if Result <> nil then
      begin
        mDetails.AppendFormat(cListDetail, [Result.Name, Result.ClassName]);
        Break;
      end;
    end;
    ADetails := mDetails.ToString;
  finally
    mClasses.Free;
    mDetails.Free;
  end;
end;

function TAtlasIdeEventLogMirror.LineCount: Integer;
begin
  Result := 0;
  if FList is TCustomListBox then
  begin
    Result := TCustomListBox(FList).Items.Count;
  end
  else if FList is TCustomListView then
  begin
    Result := TCustomListView(FList).Items.Count;
  end;
end;

function TAtlasIdeEventLogMirror.Line(AIndex: Integer): string;
var
  mItem: TListItem;
begin
  Result := '';
  if FList is TCustomListBox then
  begin
    Result := TCustomListBox(FList).Items[AIndex];
  end
  else if FList is TCustomListView then
  begin
    mItem := TCustomListView(FList).Items[AIndex];
    Result := Trim(mItem.Caption + ' ' + string.Join(' ', mItem.SubItems.ToStringArray));
  end;
end;

destructor TAtlasIdeEventLogMirror.Destroy;
begin
  Follow(nil);
  inherited Destroy;
end;

procedure TAtlasIdeEventLogMirror.Follow(AList: TWinControl);
begin
  if FList <> nil then
  begin
    FList.RemoveFreeNotification(Self);
  end;
  FList := AList;
  if FList <> nil then
  begin
    FList.FreeNotification(Self);
  end;
end;

procedure TAtlasIdeEventLogMirror.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FList) then
  begin
    FList := nil;
  end;
end;

procedure TAtlasIdeEventLogMirror.StartSession(const ALog: TProc<string>);
var
  mDetails: string;
begin
  Follow(Find(mDetails));
  FRead := LineCount;
  if not Assigned(ALog) then
  begin
    Exit;
  end;
  if FList = nil then
  begin
    ALog('Event log (#580): IDE window not found, no debug output.' + mDetails);
  end
  else
  begin
    ALog('Event log (#580): reading from' + mDetails);
  end;
end;

function TAtlasIdeEventLogMirror.NewLines: TArray<string>;
var
  mCount, mIndex: Integer;
begin
  Result := nil;
  // Verschwindet die Liste mit ihrem Formular (Notification), sucht erst die nächste Sitzung neu.
  if (FList = nil) or not FList.HandleAllocated then
  begin
    Exit;
  end;
  mCount := LineCount;
  if mCount < FRead then
  begin
    // Geleert: von vorn.
    FRead := 0;
  end;
  for mIndex := FRead to mCount - 1 do
  begin
    Result := Result + [Line(mIndex)];
  end;
  FRead := mCount;
end;

end.
