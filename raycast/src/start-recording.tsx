import {
  Action,
  ActionPanel,
  Form,
  Icon,
  launchCommand,
  LaunchType,
  List,
  LocalStorage,
  popToRoot,
  showHUD,
  useNavigation,
} from "@raycast/api";
import { usePromise } from "@raycast/utils";
import { homedir } from "node:os";
import { showError } from "./lib/errors";
import {
  ConfigInfo,
  Destination,
  elapsedSince,
  fileName,
  formatClock,
  getConfig,
  getDestinations,
  getStatus,
  INSTALL_URL,
  MictapeNotFoundError,
  startRecording,
  Status,
  stopRecording,
} from "./lib/mictape";

type Data = { status: Status; destinations: Destination[]; config: ConfigInfo };

async function load(): Promise<Data> {
  const [status, destinations, config] = await Promise.all([getStatus(), getDestinations(), getConfig()]);
  return { status, destinations, config };
}

const labelKey = (destination: Destination) => `last-label:${destination.path}`;

/** Suggests the next label: last label + 1 when it is a number, otherwise the last label. */
async function suggestLabel(destination: Destination): Promise<string> {
  const last = await LocalStorage.getItem<string>(labelKey(destination));
  if (!last) return "";
  return /^\d+$/.test(last) ? String(Number(last) + 1) : last;
}

async function refreshMenuBar() {
  try {
    await launchCommand({ name: "recording-status", type: LaunchType.Background });
  } catch {
    // The menu bar command is not enabled; nothing to refresh.
  }
}

async function start(destination: Destination, label?: string) {
  try {
    const status = await startRecording(destination.name, label);
    if (label) await LocalStorage.setItem(labelKey(destination), label);
    await refreshMenuBar();
    await showHUD(`Recording → ${fileName(status.path ?? "")}`);
    await popToRoot();
  } catch (error) {
    await showError("Could not start recording", error);
  }
}

function LabelForm({ destination }: { destination: Destination }) {
  const { data: suggested, isLoading } = usePromise(suggestLabel, [destination]);
  const { pop } = useNavigation();
  return (
    <Form
      isLoading={isLoading}
      navigationTitle={destination.name}
      actions={
        <ActionPanel>
          <Action.SubmitForm
            title="Start Recording"
            icon={Icon.Microphone}
            onSubmit={async (values: { label: string }) => {
              const label = values.label.trim();
              if (!label) return;
              await start(destination, label);
              pop();
            }}
          />
        </ActionPanel>
      }
    >
      <Form.Description title="Destination" text={destination.path.replace(homedir(), "~")} />
      {!isLoading && (
        <Form.TextField
          id="label"
          title="Label"
          placeholder="e.g. 3"
          info="Fills {label} in the file name template"
          defaultValue={suggested}
          autoFocus
        />
      )}
    </Form>
  );
}

export default function Command() {
  const { data, isLoading, error, revalidate } = usePromise(load, [], {
    onError: (e) => showError("Could not read mictape", e),
  });

  if (error instanceof MictapeNotFoundError) {
    return (
      <List>
        <List.EmptyView
          icon={Icon.Download}
          title="mictape is not installed"
          description="MicTape needs the mictape command-line tool. Install it, or set its path in the extension preferences."
          actions={
            <ActionPanel>
              <Action.OpenInBrowser title="Open Install Instructions" url={INSTALL_URL} />
            </ActionPanel>
          }
        />
      </List>
    );
  }

  if (data?.status.recording) {
    const status = data.status;
    return (
      <List isLoading={isLoading}>
        <List.EmptyView
          icon={Icon.Microphone}
          title={`Recording ${formatClock(elapsedSince(status.startedAt))}`}
          description={status.path?.replace(homedir(), "~")}
          actions={
            <ActionPanel>
              <Action
                title="Stop Recording"
                icon={Icon.Stop}
                onAction={async () => {
                  try {
                    const saved = await stopRecording();
                    await refreshMenuBar();
                    await showHUD(`Saved ${fileName(saved.path)} (${formatClock(saved.duration)})`);
                    revalidate();
                  } catch (e) {
                    await showError("Could not stop recording", e);
                  }
                }}
              />
            </ActionPanel>
          }
        />
      </List>
    );
  }

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Search destinations">
      {data && data.destinations.length === 0 && (
        <List.EmptyView
          icon={Icon.Folder}
          title="No destinations"
          description={`Add destinations to ${data.config.path.replace(homedir(), "~")}`}
        />
      )}
      {data?.destinations.map((destination) => (
        <List.Item
          key={destination.path}
          icon={Icon.Folder}
          title={destination.name}
          subtitle={destination.path.replace(homedir(), "~")}
          actions={
            <ActionPanel>
              {data.config.needsLabel ? (
                <Action.Push
                  title="Start Recording…"
                  icon={Icon.Microphone}
                  target={<LabelForm destination={destination} />}
                />
              ) : (
                <Action title="Start Recording" icon={Icon.Microphone} onAction={() => start(destination)} />
              )}
              <Action.ShowInFinder path={destination.path} />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
