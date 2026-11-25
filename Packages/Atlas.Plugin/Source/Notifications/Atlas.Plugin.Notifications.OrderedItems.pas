unit Atlas.Plugin.Notifications.OrderedItems;

// Threadsichere Liste angemeldeter Einträge mit Kennung und Reihenfolge, ohne VCL (Zeilen des Statusfelds #591,
// Bereiche der Willkommensseite #753): sortiert nach Order, bei Gleichstand nach Kennung ohne Groß-/Kleinschreibung;
// je Kennung ein Eintrag. Die Ableitung sagt, wie Kennung und Reihenfolge eines Eintrags lauten. Meldungen an
// Beobachter schickt der Besitzer der Liste selbst (TAtlasNotificationListeners).
// Gelesen wird viel öfter als geändert (Statusfeld und Kacheln bei jedem Zeichnen): Put und Remove legen ein neues
// Array an, ToArray gibt das aktuelle ohne Kopie heraus. Ein herausgegebenes Array ändert sich nie mehr.
// Gesperrt wird mit Acquire/Release statt mit den inline-Fassungen Enter/Leave: Generische Rümpfe werden in den
// Units der Module ausgeprägt, die System.SyncObjs nicht einbinden (H2443).

interface

uses
  System.SyncObjs;

type
  TAtlasOrderedItems<T> = class
  private
    FLock: TCriticalSection;
    FItems: TArray<T>;
    function IndexOf(const AItems: TArray<T>; const AId: string): Integer;
    function Comes(const ALeft, ARight: T): Boolean;
  protected
    function IdOf(const AItem: T): string; virtual; abstract;
    function OrderOf(const AItem: T): Integer; virtual; abstract;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>AItem an seiner Stelle einfügen; ein Eintrag mit derselben Kennung wird ersetzt.</summary>
    procedure Put(const AItem: T); overload;
    /// <summary>Wie oben; AReplaced ist der ersetzte Eintrag (True) bzw. Default(T) (False).</summary>
    function Put(const AItem: T; out AReplaced: T): Boolean; overload;
    /// <summary>Eintrag mit der Kennung AId entfernen; False, wenn es keinen gab.</summary>
    function Remove(const AId: string): Boolean;
    /// <summary>Wie Remove; AItem ist der entfernte Eintrag (True) bzw. Default(T) (False).</summary>
    function Take(const AId: string; out AItem: T): Boolean;
    /// <summary>Eintrag mit der Kennung AId; ohne ihn False und AItem = Default(T).</summary>
    function Find(const AId: string; out AItem: T): Boolean;
    /// <summary>Alle Einträge in ihrer Reihenfolge; das Array ändert sich danach nicht mehr.</summary>
    function ToArray: TArray<T>;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasOrderedItems<T> }

constructor TAtlasOrderedItems<T>.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
end;

destructor TAtlasOrderedItems<T>.Destroy;
begin
  FItems := nil;
  FLock.Free;
  inherited Destroy;
end;

function TAtlasOrderedItems<T>.IndexOf(const AItems: TArray<T>; const AId: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AItems) do
  begin
    if SameText(IdOf(AItems[mIndex]), AId) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasOrderedItems<T>.Comes(const ALeft, ARight: T): Boolean;
begin
  if OrderOf(ALeft) <> OrderOf(ARight) then
  begin
    Result := OrderOf(ALeft) < OrderOf(ARight);
  end
  else
  begin
    Result := CompareText(IdOf(ALeft), IdOf(ARight)) < 0;
  end;
end;

procedure TAtlasOrderedItems<T>.Put(const AItem: T);
var
  mReplaced: T;
begin
  Put(AItem, mReplaced);
end;

function TAtlasOrderedItems<T>.Put(const AItem: T; out AReplaced: T): Boolean;
var
  mItems: TArray<T>;
  mIndex, mExisting: Integer;
begin
  AReplaced := Default(T);
  FLock.Acquire;
  try
    // Neues Array: herausgegebene bleiben unverändert.
    mItems := Copy(FItems);
    mExisting := IndexOf(mItems, IdOf(AItem));
    Result := mExisting >= 0;
    if Result then
    begin
      AReplaced := mItems[mExisting];
      Delete(mItems, mExisting, 1);
    end;
    mIndex := 0;
    while (mIndex < Length(mItems)) and not Comes(AItem, mItems[mIndex]) do
    begin
      Inc(mIndex);
    end;
    Insert(AItem, mItems, mIndex);
    FItems := mItems;
  finally
    FLock.Release;
  end;
end;

function TAtlasOrderedItems<T>.Remove(const AId: string): Boolean;
var
  mItem: T;
begin
  Result := Take(AId, mItem);
end;

function TAtlasOrderedItems<T>.Take(const AId: string; out AItem: T): Boolean;
var
  mItems: TArray<T>;
  mIndex: Integer;
begin
  AItem := Default(T);
  FLock.Acquire;
  try
    mIndex := IndexOf(FItems, AId);
    Result := mIndex >= 0;
    if Result then
    begin
      AItem := FItems[mIndex];
      mItems := Copy(FItems);
      Delete(mItems, mIndex, 1);
      FItems := mItems;
    end;
  finally
    FLock.Release;
  end;
end;

function TAtlasOrderedItems<T>.Find(const AId: string; out AItem: T): Boolean;
var
  mIndex: Integer;
begin
  FLock.Acquire;
  try
    mIndex := IndexOf(FItems, AId);
    Result := mIndex >= 0;
    if Result then
    begin
      AItem := FItems[mIndex];
    end
    else
    begin
      AItem := Default(T);
    end;
  finally
    FLock.Release;
  end;
end;

function TAtlasOrderedItems<T>.ToArray: TArray<T>;
begin
  FLock.Acquire;
  try
    Result := FItems;
  finally
    FLock.Release;
  end;
end;

end.
