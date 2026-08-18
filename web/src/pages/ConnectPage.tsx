import { Button } from "../bflabs/Button";
import { Notice } from "../bflabs/Notice";
import { Tabs } from "../bflabs/Tabs";
import { RECIPE_ORDER, type RecipeName } from "../recipes";
import { PageFrame } from "./shared";

const RECIPE_LABEL: Record<RecipeName, string> = {
  claude: "Claude Code",
  grok: "Grok Build",
  openai: "OpenAI SDK",
  newapi: "new-api",
};

export function ConnectPage({
  t,
  origin,
  copied,
  recipe,
  snippets,
  routes,
  gatewayKey,
  authMode,
  keyRevealed,
  onRevealKey,
  onCopy,
  onRecipe,
}: {
  t: {
    title: string;
    origin: string;
    copy: string;
    copied: string;
    recipes: string;
    routeTitle: string;
    routeClient: string;
    routeEndpoint: string;
    routeNote: string;
    workspaceTitle: string;
    workspaceBody: string;
    keyLabel: string;
    keyReveal: string;
    keyHide: string;
    keyHelp: string;
    keyByok: string;
    keyUnavailable: string;
  };
  origin: string;
  copied: string;
  recipe: RecipeName;
  snippets: Record<RecipeName, string>;
  routes: Array<{ client: string; endpoint: string; note: string }>;
  gatewayKey: string | null;
  authMode: "managed" | "byok";
  keyRevealed: boolean;
  onRevealKey: (next: boolean) => void;
  onCopy: (label: string, value: string) => void;
  onRecipe: (value: RecipeName) => void;
}) {
  return (
    <PageFrame title={t.title}>
      <div className="home-origin">
        <div>
          <p className="kicker">{t.origin}</p>
          <p className="origin mono">{origin}</p>
        </div>
        <Button variant="secondary" size="sm" data-copied={copied === "origin" ? "true" : undefined} onClick={() => onCopy("origin", origin)}>{copied === "origin" ? t.copied : t.copy}</Button>
      </div>
      <div className="home-origin">
        <div>
          <p className="kicker">{t.keyLabel}</p>
          <p className="origin mono">
            {authMode === "byok"
              ? t.keyByok
              : gatewayKey
                ? keyRevealed
                  ? gatewayKey
                  : `${gatewayKey.slice(0, 6)}${"•".repeat(12)}${gatewayKey.slice(-4)}`
                : t.keyUnavailable}
          </p>
          <p className="note">{t.keyHelp}</p>
        </div>
        {authMode === "managed" && gatewayKey ? (
          <div className="recipe-tools">
            <Button variant="quiet" size="sm" onClick={() => onRevealKey(!keyRevealed)}>
              {keyRevealed ? t.keyHide : t.keyReveal}
            </Button>
            <Button variant="secondary" size="sm" data-copied={copied === "key" ? "true" : undefined} onClick={() => onCopy("key", gatewayKey)}>
              {copied === "key" ? t.copied : t.copy}
            </Button>
          </div>
        ) : null}
      </div>
      <ul className="endpoints page-endpoints">
        <li><span>POST</span><code>/v1/messages</code></li>
        <li><span>POST</span><code>/v1/chat/completions</code></li>
        <li><span>POST</span><code>/v1/responses</code></li>
        <li><span>GET</span><code>/v1/models</code></li>
        <li><span>GET</span><code>/v1/account</code></li>
      </ul>
      <h2 className="subhead">{t.routeTitle}</h2>
      <table className="route-map">
        <thead>
          <tr>
            <th>{t.routeClient}</th>
            <th>{t.routeEndpoint}</th>
            <th>{t.routeNote}</th>
          </tr>
        </thead>
        <tbody>
          {routes.map((row) => (
            <tr key={row.client}>
              <th scope="row">{row.client}</th>
              <td><code>{row.endpoint}</code></td>
              <td>{row.note}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <Notice title={t.workspaceTitle} description={t.workspaceBody} />
      <h2 className="subhead">{t.recipes}</h2>
      <Tabs
        label={t.recipes}
        value={recipe}
        onValueChange={(value) => onRecipe(value as RecipeName)}
        items={RECIPE_ORDER.map((name) => ({
          value: name,
          label: RECIPE_LABEL[name],
          content: (
            <div>
              <div className="recipe-tools">
                <Button variant="secondary" size="sm" data-copied={copied === "recipe" ? "true" : undefined} onClick={() => onCopy("recipe", snippets[name])}>
                  {copied === "recipe" ? t.copied : t.copy}
                </Button>
              </div>
              <pre className="snip">{snippets[name]}</pre>
            </div>
          ),
        }))}
      />
    </PageFrame>
  );
}
