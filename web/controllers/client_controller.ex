defmodule Shield.ClientController do
  use Shield.Web, :controller
  use Shield.HookImporter
  alias Shield.Query.Client, as: ClientQuery

  @repo Application.get_env(:authable, :repo)
  @client Application.get_env(:authable, :client)
  @views Application.get_env(:shield, :views)
  @hooks Application.get_env(:shield, :hooks)

  plug :scrub_params, "client" when action in [:create, :update]
  plug :before_client_create when action in [:create]
  plug :before_client_update when action in [:update]
  plug :before_client_delete when action in [:delete]
  plug Authable.Plug.Authenticate, [scopes: ~w(session read)] when action in [:index]
  plug Authable.Plug.Authenticate, [scopes: ~w(session read write)] when action in [:create, :update, :delete]
  plug Shield.Arm.Confirmable, [enabled: Application.get_env(:shield, :confirmable)]

  # GET /clients
  def index(conn, _params) do
    clients =
      conn.assigns[:current_user]
      |> ClientQuery.user_clients()
      |> @repo.all()

    render(conn, @views[:client], "index.json", clients: clients)
  end

  # POST /clients
  def create(conn, %{"client" => client_params}) do
    client_params = Map.put(client_params, "user_id",
                            conn.assigns[:current_user].id)
    changeset = @client.changeset(%@client{}, client_params)

    case @repo.insert(changeset) do
      {:ok, client} ->
        conn
        |> @hooks.after_client_create_success(client)
        |> put_status(:created)
        |> put_resp_header("location", client_path(conn, :show, client))
        |> render(@views[:client], "show.json", client: client)
      {:error, changeset} ->
        conn
        |> @hooks.after_client_create_failure(changeset)
        |> put_status(:unprocessable_entity)
        |> render(@views[:changeset],  "error.json",
                  changeset: changeset)
    end
  end

  # GET /clients/:id
  def show(conn, %{"id" => id}) do
    conn = assign_current_user(conn)

    case @repo.get(@client, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> render(@views[:error], "404.json")
      client ->
        is_owner = conn.assigns[:current_user] &&
          conn.assigns[:current_user].id == client.user_id

        render(conn, @views[:client], "show.json", client: client,
          is_owner: is_owner)
    end
  end

  # PUT /clients/:id
  def update(conn, %{"id" => id, "client" => client_params}) do
    client =
      conn.assigns[:current_user]
      |> ClientQuery.user_client(id)
      |> @repo.get_by!([])

    client_params = Map.put(client_params, "user_id",
      conn.assigns[:current_user].id)
    changeset = @client.changeset(client, client_params)

    case @repo.update(changeset) do
      {:ok, client} ->
        conn
        |> @hooks.after_client_update_success(client)
        |> put_status(:ok)
        |> render(@views[:client], "show.json", client: client)
      {:error, changeset} ->
        conn
        |> @hooks.after_client_update_failure(changeset)
        |> put_status(:unprocessable_entity)
        |> render(@views[:changeset], "error.json",
                  changeset: changeset)
    end
  end

  # DELETE /clients/:id
  def delete(conn, %{"id" => id}) do
    client =
      conn.assigns[:current_user]
      |> ClientQuery.user_client(id)
      |> @repo.get_by!([])

    @repo.delete!(client)

    conn
    |> @hooks.after_client_delete
    |> send_resp(:no_content, "")
  end

  defp assign_current_user(conn) do
    user = case Authable.Helper.authorize_for_resource(conn, ~w(session)) do
      {:ok, user} -> user
      _ -> nil
    end

    assign(conn, :current_user, user)
  end
end
