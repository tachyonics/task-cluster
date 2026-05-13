const cdk = require('aws-cdk-lib');
const { Stack } = require('aws-cdk-lib');
const dynamodb = require('aws-cdk-lib/aws-dynamodb');

// Stack 1 — runtime dependencies for the TaskCluster service.
//
// Deployed identically to LocalStack (for tests) and to real AWS (for prod).
// The hosting stack (Stack 2 — ECS / API Gateway) lives alongside this one
// and consumes the outputs below to wire env vars on the task definition.
class TaskClusterDependenciesStack extends Stack {
  constructor(scope, id, props) {
    super(scope, id, props);

    // Composite primary key: PK + SK (matches StandardCompositePrimaryKey
    // in the dynamo-db-tables library used by DynamoDBTaskRepository).
    const taskTable = new dynamodb.Table(this, 'TaskTable', {
      partitionKey: { name: 'PK', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'SK', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    new cdk.CfnOutput(this, 'TaskTableName', {
      value: taskTable.tableName,
    });
  }
}

const app = new cdk.App();
new TaskClusterDependenciesStack(app, 'TaskClusterDependenciesStack');
