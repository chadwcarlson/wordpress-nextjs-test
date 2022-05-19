#!/usr/bin/env bash
# Generates a refresh token nextjs can use to do post previews
# We need to get a refresh token from wpgraphql and then store it as an environmental variable named
# WORDPRESS_AUTH_REFRESH_TOKEN that is loaded into the nextjs app container.
# In order to get the refresh token, we need to do the following:
# 1. Find an administrator user - if none, create one?
# 2. See if they already have an application password for nextjs - if so, delete it?
# 3. Create an application password for nextjs and capture its value
# 4. Make the following GraphQL mutation:
# mutation Login {
  #  login(
  #    input: {
  #      clientMutationId: "uniqueId"
  #      password: "<generated-application-password>"
  #      username: "<administrator-user-we-found>"
  #    }
  #  ) {
  #    refreshToken
  #  }
  #}
# 5. Capture returned token, data.login.refreshToken
# 6. Store its value as WORDPRESS_AUTH_REFRESH_TOKEN that is stored in $VARS_PSH (platformsh.environment)

previewUser=$(jq -r '.environment.consumer.name' < "${ENV_SETTINGS}");
previewAppName=$(jq -r '.environment.consumer.application_password_name' < "${ENV_SETTINGS}")

# see if we already have an password for the given app name, if so, delete it
# We dont want to store a *password* on the file system, and we can't set or update an application password. Therefore,
# since we have to have the actual password to create the wpgraphql refresh token, we'll have to delete the old password
# and recreate it, so we can temporarily hold the password to give to wpgrapql
if $(wp user application-password exists "${previewUser}" "${previewAppName}"); then
	# in order to delete the app password so we can recreate it, we have to retrieve its uuid first
	previewAppUUID=$(wp user application-password list "${previewUser}" --name="${previewAppName}" --fields=uuid --format=csv | tail -n +2)
	# now we can delete it
	wp user application-password delete "${previewUser}" "${previewAppUUID}"
fi

# we need to create and store an application password that we can then turn around and use with graphql to get a refresh token
previewAppPassword=$(wp user application-password create "${previewUser}" "$previewAppName" --porcelain)

#now we can get our refresh token!
mutation=printf '{ "mutation": "mutation Login { login( input: { clientMutationId: \"%s\" password: \"%s\" username: \"%s\" } ) { refreshToken } }" }' "${previewAppName}${RANDOM}"
curl -H "Content-Type: application/json" -d ''
{ "mutation": "mutation Login { login( input: { clientMutationId: \"uniqueId\" password: \"your_password\" username: \"your_username\" } ) { refreshToken } }" }

previewAppMutation=$(printf '{
	"query": "mutation Login {
	  login(
	  	input: {
	  	  clientMutationId: \\"%s\\"
	  	  password: \\"%s\\"
	  	  username: \\"%s\\"
	  	}
	  ) {
	  	refreshToken
	  }
	}"
  }' "${previewAppName}${RANDOM}" "${previewAppPassword}" "${previewUser}" | jq -r tostring)

# still need to get WORDPRESS_API_URL from the settings file

WORDPRESS_AUTH_REFRESH_TOKEN=$(curl -H "Content-type: application/json" -d ''  -X POST https://api.test1-dnhq5ga-z6d5mdnrun4va.ca-1.platformsh.site/graphql | jq -r '.data.login.refreshToken')

UPDATED_SETTINGS=$(jq --arg WPTOKEN "${wpGraphqlUserID}" '.environment.consumer.secret = $WPTOKEN' "$ENV_SETTINGS")
echo "${UPDATED_SETTINGS}" > "$ENV_SETTINGS"
